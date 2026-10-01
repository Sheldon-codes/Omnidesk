import CallKit
import AVFAudio
import Flutter
import PushKit
import os.log
import UIKit

/// PushKit must report an offer to CallKit promptly rather than waiting for
/// Flutter. Offers and actions are persisted until the Dart engine is ready.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  PKPushRegistryDelegate, CXProviderDelegate
{
  private let callChannelName = "africa.omnidesk/calls"
  private let voipTokenKey = "omnidesk.voipPushToken"
  private let pendingOfferKey = "omnidesk.pendingCallOffer"
  private let pendingActionKey = "omnidesk.pendingCallAction"
  private let reportedIncomingCallKey = "omnidesk.reportedIncomingCallId"
  private let incomingPresentationReceiptKey = "omnidesk.incomingPresentationReceipt"
  private let callUuidPrefix = "omnidesk.callUuid."
  private var answeredCallUuids = Set<UUID>()

  private var voipRegistry: PKPushRegistry?
  private var callChannel: FlutterMethodChannel?
  // CallKit owns activation/deactivation. We only retain the desired route so
  // a speaker selection made while WebRTC is connecting is applied as soon as
  // CallKit supplies the active AVAudioSession.
  private var speakerRequested = false
  // Keep the shared CallKit session available for Dart's immediate readiness
  // probe; a weak reference can turn nil after activation has already fired.
  private var activeCallAudioSession: AVAudioSession?
  private let callController = CXCallController()
  private let mediaLogger = Logger(subsystem: "com.bigbrainzsolutions.omnidesk", category: "NativeCallMedia")
  private lazy var callProvider: CXProvider = {
    let configuration = CXProviderConfiguration(localizedName: "OmniDesk")
    configuration.supportsVideo = false
    configuration.includesCallsInRecents = false
    configuration.maximumCallsPerCallGroup = 1
    configuration.maximumCallGroups = 1
    let provider = CXProvider(configuration: configuration)
    provider.setDelegate(self, queue: nil)
    return provider
  }()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // CallKit must know about our CXProvider before a CXCallController submits
    // an outgoing CXStartCallAction. Incoming calls already instantiate this
    // provider through reportNewIncomingCall, but an outbound call on a cold
    // launch otherwise reaches CallKit with no registered provider and is
    // rejected as CXErrorCodeRequestTransactionErrorUnknownCallProvider.
    ensureCallProvider()
    observeAudioSessionLifecycle()
    configureVoipPush()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Materializes the process-wide CallKit provider. Keeping this explicit is
  /// important because [callProvider] is lazy: outbound calls do not otherwise
  /// reference it before requesting their first transaction.
  private func ensureCallProvider() {
    _ = callProvider
  }

  private func observeAudioSessionLifecycle() {
    let center = NotificationCenter.default
    center.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.emitAudioSessionDiagnostic("route_changed")
    }
    center.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let rawType = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
      self?.emitAudioSessionDiagnostic("interruption_\(rawType)")
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: callChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleFlutterCall(call, result: result)
    }
    callChannel = channel
  }

  private func configureVoipPush() {
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate credentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    UserDefaults.standard.set(token, forKey: voipTokenKey)
    callChannel?.invokeMethod("voipPushToken", arguments: ["token": token])
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    UserDefaults.standard.removeObject(forKey: voipTokenKey)
    callChannel?.invokeMethod("voipPushToken", arguments: ["token": ""])
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    let payload_dict = payload.dictionaryPayload as? [String: Any] ?? [:]
    // Cancellation must never report a new CallKit call: it ends the existing
    // one (caller hangup, answered elsewhere, offer expired, rerouted). This
    // mirrors Android's FCM `call_cancelled` → Telecom.cancel path.
    if (payload_dict["type"] as? String)?.lowercased() == "call_cancelled" {
      handleCancelPush(payload_dict)
      completion()
      return
    }
    let offer = payload_dict
    guard let callId = offer["call_id"] as? String, !callId.isEmpty,
      let offerId = offer["offer_id"] as? String, !offerId.isEmpty,
      let number = offer["caller_number"] as? String, !number.isEmpty
    else {
      // iOS 13+ penalizes VoIP pushes that never report to CallKit (repeated
      // offenses stop waking the app). Never silently drop: report a generic
      // call so the push counts as delivered, then end it immediately so no
      // ghost UI lingers. Dart cannot accept it (no IDs) — backend must
      // always send call_id/offer_id/caller_number for real calls.
      let fallbackId = "invalid-\(Int(Date().timeIntervalSince1970))"
      let fallbackUpdate = CXCallUpdate()
      fallbackUpdate.localizedCallerName = "Unknown caller"
      fallbackUpdate.remoteHandle = CXHandle(type: .phoneNumber, value: "Unknown")
      fallbackUpdate.hasVideo = false
      fallbackUpdate.supportsHolding = false
      fallbackUpdate.supportsGrouping = false
      fallbackUpdate.supportsUngrouping = false
      let fallbackUuid = uuid(for: fallbackId)
      callProvider.reportNewIncomingCall(with: fallbackUuid, update: fallbackUpdate) { [weak self] _ in
        self?.callProvider.reportCall(with: fallbackUuid, endedAt: Date(), reason: .failed)
        self?.removeUuid(for: fallbackId)
        completion()
      }
      return
    }
    var persistable = offer
    persistable["call_id"] = callId
    persistable["offer_id"] = offerId
    persistable["caller_number"] = number
    UserDefaults.standard.set(persistable, forKey: pendingOfferKey)
    reportIncoming(offer: persistable) { [weak self] reported in
      // `pendingOfferKey` is the durable source of truth. The immediate
      // signal removes latency for a warm Flutter engine; a cold engine drains
      // the same offer during authenticated startup. Crucially, CallKit's
      // answer action alone has no offer payload, so Flutter must receive this
      // signal before it can issue /calls/{id}/accept.
      if reported {
        self?.callChannel?.invokeMethod("offerAvailable", arguments: ["callId": callId])
      }
      completion()
    }
  }

  private func reportIncoming(offer: [String: Any], completion: @escaping (Bool) -> Void) {
    guard let callId = offer["call_id"] as? String else {
      completion(false)
      return
    }
    // PushKit has already reported this UUID to CallKit. When Flutter drains
    // its persisted offer it calls `presentIncoming` as part of the shared
    // cross-platform contract; reporting it again can make CallKit reject the
    // duplicate UUID and prevents the backend delivery acknowledgement.
    if UserDefaults.standard.string(forKey: reportedIncomingCallKey) == callId {
      completion(true)
      return
    }
    let update = CXCallUpdate()
    let callerName = (offer["caller_name"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    update.localizedCallerName = (callerName?.isEmpty == false)
      ? callerName : offer["caller_number"] as? String
    update.remoteHandle = CXHandle(
      type: .phoneNumber,
      value: offer["caller_number"] as? String ?? "Unknown"
    )
    update.hasVideo = false
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    callProvider.reportNewIncomingCall(with: uuid(for: callId), update: update) { [weak self] error in
      guard let self else {
        completion(false)
        return
      }
      if error != nil {
        UserDefaults.standard.removeObject(forKey: self.pendingOfferKey)
        self.removeUuid(for: callId)
        completion(false)
        return
      }
      let presentedAt = ISO8601DateFormatter().string(from: Date())
      let receivedAt = offer["timestamp"] as? String ?? presentedAt
      UserDefaults.standard.set(callId, forKey: self.reportedIncomingCallKey)
      UserDefaults.standard.set([
        "callId": callId,
        "receivedAt": receivedAt,
        "nativePresentedAt": presentedAt,
      ], forKey: self.incomingPresentationReceiptKey)
      completion(true)
    }
  }

  /// Ends the CallKit call for a `call_cancelled` VoIP push without reporting
  /// a new incoming call. Clears durable offer state when IDs match so a
  /// cancelled offer can never be accepted afterwards, then notifies Dart via
  /// the existing `disconnected` path (same as Android's cancel handling).
  private func handleCancelPush(_ payload: [String: Any]) {
    guard let callId = payload["call_id"] as? String, !callId.isEmpty else { return }
    let reason = (payload["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let nonEmptyReason = (reason?.isEmpty == false) ? reason! : "call_cancelled"
    if let pending = UserDefaults.standard.dictionary(forKey: pendingOfferKey),
      (pending["call_id"] as? String) == callId {
      UserDefaults.standard.removeObject(forKey: pendingOfferKey)
    }
    if UserDefaults.standard.string(forKey: reportedIncomingCallKey) == callId {
      UserDefaults.standard.removeObject(forKey: reportedIncomingCallKey)
      UserDefaults.standard.removeObject(forKey: incomingPresentationReceiptKey)
    }
    callProvider.reportCall(with: uuid(for: callId), endedAt: Date(), reason: .remoteEnded)
    removeUuid(for: callId)
    callChannel?.invokeMethod("disconnected", arguments: ["callId": callId, "reason": nonEmptyReason])
    let pendingAction = UserDefaults.standard.dictionary(forKey: pendingActionKey)
    if (pendingAction?["callId"] as? String) == callId {
      UserDefaults.standard.removeObject(forKey: pendingActionKey)
    }
  }

  private func incomingPresentationReceipt(for callId: String) -> [String: Any] {
    let receipt = UserDefaults.standard.dictionary(forKey: incomingPresentationReceiptKey)
    guard receipt?["callId"] as? String == callId else { return [:] }
    return [
      "receivedAt": receipt?["receivedAt"] as? String ?? ISO8601DateFormatter().string(from: Date()),
      "nativePresentedAt": receipt?["nativePresentedAt"] as? String ?? ISO8601DateFormatter().string(from: Date()),
    ]
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    answeredCallUuids.insert(action.callUUID)
    prepareCallAudioSession(reason: "answer_action")
    forwardNativeAction("answer", uuid: action.callUUID)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    prepareCallAudioSession(reason: "outgoing_start_action")
    provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    forwardNativeAction("end", uuid: action.callUUID)
    if let callId = callId(for: action.callUUID),
      UserDefaults.standard.string(forKey: reportedIncomingCallKey) == callId {
      UserDefaults.standard.removeObject(forKey: reportedIncomingCallKey)
      UserDefaults.standard.removeObject(forKey: incomingPresentationReceiptKey)
    }
    if let callId = callId(for: action.callUUID) {
      removeUuid(for: callId)
    }
    answeredCallUuids.remove(action.callUUID)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
    // WebRTC-in-WebView owns hold via Dart; CallKit UI must not offer it.
    action.fail()
  }

  func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
    // Flutter never completed (e.g. killed, auth-gated). Clear durable state
    // so a stale UUID cannot end a newer call, then fail the transaction.
    UserDefaults.standard.removeObject(forKey: pendingActionKey)
    action.fail()
  }

  func providerDidReset(_ provider: CXProvider) {
    mediaLogger.info("CallKit provider reset")
    UserDefaults.standard.removeObject(forKey: pendingActionKey)
    answeredCallUuids.removeAll()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    activeCallAudioSession = audioSession
    do {
      // WKWebView WebRTC must share CallKit's already-active session. Do not
      // call setActive here: CallKit is the sole activation authority. The
      // play-and-record/voice-chat configuration supplies bidirectional audio
      // and preserves a receiver default until the agent explicitly selects
      // loudspeaker.
      try configureCallAudioSession(audioSession, speaker: speakerRequested)
      mediaLogger.info(
        "CallKit audio activated category=\(audioSession.category.rawValue, privacy: .public) mode=\(audioSession.mode.rawValue, privacy: .public) route=\(self.audioRouteDescription(audioSession), privacy: .public) speaker=\(self.speakerRequested, privacy: .public)"
      )
      emitAudioSessionDiagnostic("callkit_activated", session: audioSession)
      // This is deliberately separate from the diagnostic stream: Dart uses
      // it as the readiness edge before asking WKWebView to capture audio.
      callChannel?.invokeMethod("systemAudioActive", arguments: ["phase": "callkit_activated"])
    } catch {
      mediaLogger.error(
        "CallKit audio configuration failed error=\(error.localizedDescription, privacy: .public)"
      )
      emitAudioSessionDiagnostic("callkit_activation_configuration_failed", session: audioSession)
    }
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    activeCallAudioSession = nil
    mediaLogger.info("CallKit audio deactivated")
    emitAudioSessionDiagnostic("callkit_deactivated", session: audioSession)
    callChannel?.invokeMethod("systemAudioInactive", arguments: ["phase": "callkit_deactivated"])
  }

  /// Category configuration is safe before CallKit activates the session; it
  /// makes the process eligible for bidirectional voice capture. Activation
  /// itself remains exclusively CallKit-owned and happens in didActivate.
  private func prepareCallAudioSession(reason: String) {
    let session = AVAudioSession.sharedInstance()
    do {
      try configureCallAudioSession(session, speaker: speakerRequested)
      mediaLogger.info("Prepared CallKit audio session reason=\(reason, privacy: .public)")
      emitAudioSessionDiagnostic("prepared_\(reason)", session: session)
    } catch {
      mediaLogger.error(
        "Failed to prepare CallKit audio session reason=\(reason, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
      )
      emitAudioSessionDiagnostic("prepare_failed_\(reason)", session: session)
    }
  }

  private func configureCallAudioSession(
    _ audioSession: AVAudioSession,
    speaker: Bool
  ) throws {
    // `allowBluetooth` enables the bidirectional HFP route required for a
    // voice call. Deliberately omit `defaultToSpeaker`: speaker must be an
    // explicit, reversible agent choice, while the normal default remains the
    // receiver (or an attached headset).
    try audioSession.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.allowBluetooth]
    )
    try audioSession.overrideOutputAudioPort(speaker ? .speaker : .none)
  }

  private func audioRouteDescription(_ audioSession: AVAudioSession) -> String {
    let outputs = audioSession.currentRoute.outputs.map { $0.portType.rawValue }
    return outputs.isEmpty ? "none" : outputs.joined(separator: ",")
  }

  /// os.Logger does not appear in flutter run output. Mirror a strictly
  /// allowlisted audio-session snapshot through the existing channel so an
  /// on-device WebRTC investigation can correlate CallKit activation with the
  /// bridge's local-track state. No device IDs, call IDs, credentials, or
  /// audio data are included.
  private func emitAudioSessionDiagnostic(
    _ phase: String,
    session: AVAudioSession = AVAudioSession.sharedInstance()
  ) {
    callChannel?.invokeMethod("audioSessionDiagnostic", arguments: [
      "phase": phase,
      "category": session.category.rawValue,
      "mode": session.mode.rawValue,
      "route": audioRouteDescription(session),
      "inputAvailable": session.isInputAvailable,
      "speakerRequested": speakerRequested,
    ])
  }

  private func forwardNativeAction(_ action: String, uuid: UUID) {
    guard let callId = callId(for: uuid) else { return }
    let payload: [String: String] = ["action": action, "callId": callId]
    UserDefaults.standard.set(payload, forKey: pendingActionKey)
    callChannel?.invokeMethod(action, arguments: ["callId": callId])
  }

  private func handleFlutterCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "readVoipPushToken", "readNativePushToken":
      result(UserDefaults.standard.string(forKey: voipTokenKey))
    case "takePendingOffer":
      let offer = UserDefaults.standard.dictionary(forKey: pendingOfferKey)
      UserDefaults.standard.removeObject(forKey: pendingOfferKey)
      result(offer)
    case "takePendingAction":
      let action = UserDefaults.standard.dictionary(forKey: pendingActionKey)
      UserDefaults.standard.removeObject(forKey: pendingActionKey)
      result(action)
    case "presentIncoming":
      guard let args = call.arguments as? [String: Any],
        let callId = args["callId"] as? String
      else {
        result(FlutterError(code: "invalid_offer", message: "Missing call ID", details: nil))
        return
      }
      var offer = args
      offer["call_id"] = callId
      offer["caller_number"] = args["callerNumber"] as? String ?? "Unknown"
      reportIncoming(offer: offer) { [weak self] reported in
        guard reported else {
          result(FlutterError(
            code: "incoming_presentation_failed",
            message: "CallKit could not present the incoming call.",
            details: nil
          ))
          return
        }
        result(self?.incomingPresentationReceipt(for: callId) ?? [:])
      }
    case "beginOutgoingSystemCall":
      guard let args = call.arguments as? [String: Any],
        let identity = (args["callId"] as? String) ?? (args["callSid"] as? String),
        !identity.isEmpty
      else {
        result(FlutterError(code: "invalid_call", message: "Missing call identity", details: nil))
        return
      }
      // Be defensive in case this handler is ever invoked before normal app
      // startup has completed (for example, during engine restoration).
      ensureCallProvider()
      let handle = CXHandle(type: .phoneNumber, value: args["phoneNumber"] as? String ?? "Unknown")
      let action = CXStartCallAction(call: uuid(for: identity), handle: handle)
      action.contactIdentifier = args["displayName"] as? String
      callController.request(CXTransaction(action: action)) { error in
        if let error {
          result(FlutterError(code: "callkit_outgoing_failed", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    case "markSystemCallActive":
      guard let identity = systemCallIdentity(from: call.arguments) else { result(nil); return }
      callProvider.reportOutgoingCall(with: uuid(for: identity), connectedAt: Date())
      result(nil)
    case "markSystemCallAnswering":
      guard let identity = systemCallIdentity(from: call.arguments) else { result(nil); return }
      let callUuid = uuid(for: identity)
      // Native CallKit Answer already reached this process before Flutter's
      // action drain in the common case. Flutter UI Answer requests the same
      // action exactly once so CallKit owns ringing cessation and activation.
      if answeredCallUuids.contains(callUuid) {
        result(nil)
        return
      }
      callController.request(CXTransaction(action: CXAnswerCallAction(call: callUuid))) { error in
        if let error {
          result(FlutterError(code: "callkit_answer_failed", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    case "isSystemAudioActive":
      result(activeCallAudioSession != nil)
    case "markSystemCallFailed", "dismissSystemCall", "dismiss":
      guard let identity = systemCallIdentity(from: call.arguments) else { result(nil); return }
      callProvider.reportCall(with: uuid(for: identity), endedAt: Date(), reason: .remoteEnded)
      result(nil)
    case "setSpeaker", "setSystemSpeaker":
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
      speakerRequested = enabled
      do {
        let audioSession = activeCallAudioSession ?? AVAudioSession.sharedInstance()
        try configureCallAudioSession(audioSession, speaker: enabled)
        mediaLogger.info(
          "Speaker route updated enabled=\(enabled, privacy: .public) category=\(audioSession.category.rawValue, privacy: .public) route=\(self.audioRouteDescription(audioSession), privacy: .public)"
        )
        emitAudioSessionDiagnostic("speaker_updated", session: audioSession)
        result(nil)
      } catch {
        mediaLogger.error(
          "Speaker route update failed enabled=\(enabled, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
        )
        emitAudioSessionDiagnostic("speaker_update_failed")
        result(FlutterError(code: "audio_route_failed", message: error.localizedDescription, details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func systemCallIdentity(from arguments: Any?) -> String? {
    guard let args = arguments as? [String: Any] else { return nil }
    if let callId = args["callId"] as? String, !callId.isEmpty { return callId }
    if let callSid = args["callSid"] as? String, !callSid.isEmpty { return callSid }
    return nil
  }

  private func uuid(for callId: String) -> UUID {
    let key = callUuidPrefix + callId
    if let raw = UserDefaults.standard.string(forKey: key), let existing = UUID(uuidString: raw) {
      return existing
    }
    let created = UUID()
    UserDefaults.standard.set(created.uuidString, forKey: key)
    return created
  }

  private func removeUuid(for callId: String) {
    UserDefaults.standard.removeObject(forKey: callUuidPrefix + callId)
  }

  private func callId(for uuid: UUID) -> String? {
    let prefix = callUuidPrefix
    for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
      guard key.hasPrefix(prefix), let raw = value as? String,
        raw.caseInsensitiveCompare(uuid.uuidString) == .orderedSame
      else { continue }
      return String(key.dropFirst(prefix.count))
    }
    return nil
  }
}
