import CallKit
import Flutter
import PushKit
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
  private let callUuidPrefix = "omnidesk.callUuid."

  private var voipRegistry: PKPushRegistry?
  private var callChannel: FlutterMethodChannel?
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
    configureVoipPush()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
    let offer = payload.dictionaryPayload as? [String: Any] ?? [:]
    guard let callId = offer["call_id"] as? String, !callId.isEmpty,
      let offerId = offer["offer_id"] as? String, !offerId.isEmpty,
      let number = offer["caller_number"] as? String, !number.isEmpty
    else {
      completion()
      return
    }
    var persistable = offer
    persistable["call_id"] = callId
    persistable["offer_id"] = offerId
    persistable["caller_number"] = number
    UserDefaults.standard.set(persistable, forKey: pendingOfferKey)
    reportIncoming(offer: persistable, completion: completion)
  }

  private func reportIncoming(offer: [String: Any], completion: @escaping () -> Void) {
    guard let callId = offer["call_id"] as? String else {
      completion()
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
    update.supportsHolding = true
    update.supportsGrouping = false
    update.supportsUngrouping = false
    callProvider.reportNewIncomingCall(with: uuid(for: callId), update: update) { error in
      if error != nil {
        UserDefaults.standard.removeObject(forKey: self.pendingOfferKey)
      }
      completion()
    }
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    forwardNativeAction("answer", uuid: action.callUUID)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    forwardNativeAction("end", uuid: action.callUUID)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
    // A genuine SIP stack owns media hold. Never pretend it succeeded.
    action.fail()
  }

  func providerDidReset(_ provider: CXProvider) {
    UserDefaults.standard.removeObject(forKey: pendingActionKey)
  }

  private func forwardNativeAction(_ action: String, uuid: UUID) {
    guard let callId = callId(for: uuid) else { return }
    let payload: [String: String] = ["action": action, "callId": callId]
    UserDefaults.standard.set(payload, forKey: pendingActionKey)
    callChannel?.invokeMethod(action, arguments: ["callId": callId])
  }

  private func handleFlutterCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "readVoipPushToken":
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
      reportIncoming(offer: offer) { result(nil) }
    case "dismiss":
      guard let args = call.arguments as? [String: Any],
        let callId = args["callId"] as? String
      else {
        result(nil)
        return
      }
      callProvider.reportCall(with: uuid(for: callId), endedAt: Date(), reason: .remoteEnded)
      result(nil)
    case "registerMedia", "endMedia", "setMuted", "setSpeaker", "setHeld", "sendDtmf":
      result(FlutterError(
        code: "native_media_not_configured",
        message: "The native SIP media transport is not configured.",
        details: nil
      ))
    default:
      result(FlutterMethodNotImplemented)
    }
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
