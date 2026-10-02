import AVFAudio
import Flutter
import Foundation
import WebRTC

/// Flutter adapter for the isolated iOS AT signaling + native WebRTC engine.
/// CallKit continues to own AVAudioSession activation; Android/WebView paths
/// remain outside this class.
final class ATNativeMediaChannel {
  static let name = "africa.omnidesk/media"

  private let channel: FlutterMethodChannel
  private let signaling = ATSignalingClient()
  private let rtc = ATWebRTCSession()
  private var sessionID: String?
  private var callSid: String?
  private var incomingCallID: String?
  private var pendingIncomingOffer: [String: Any]?
  private var answerInProgress = false
  private var pendingAnswerResult: FlutterResult?
  private var callAccepted = false
  private var connectedEmitted = false
  private var peerConnected = false
  private var callRequestSent = false
  private var pendingLocalCandidates: [[String: Any]?] = []
  private var connectionTimeout: Timer?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.name, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    let audio = RTCAudioSession.sharedInstance()
    audio.useManualAudio = true
    audio.isAudioEnabled = false

    signaling.onHandshake = { [weak self] selected, result in
      self?.emit("diagnostic", payload: ["phase": "gateway_handshake", "negotiatedProtocol": selected, "result": result])
    }
    signaling.onEvent = { [weak self] event in
      DispatchQueue.main.async { self?.handleSignaling(event) }
    }
    signaling.onClosed = { [weak self] error in
      DispatchQueue.main.async {
        guard let self else { return }
        self.emit("processTerminated", payload: ["reason": error == nil ? "closed" : "transport_error"])
        self.finishCall(reason: "signaling_closed", sendHangup: false)
      }
    }
    rtc.onLocalCandidate = { [weak self] candidate in
      DispatchQueue.main.async {
        guard let self else { return }
        if self.callRequestSent { self.signaling.sendTrickle(candidate) }
        else { self.pendingLocalCandidates.append(candidate) }
      }
    }
    rtc.onConnectionState = { [weak self] state in
      DispatchQueue.main.async {
        guard let self else { return }
        switch state {
        case .connected:
          self.peerConnected = true
          self.emit("diagnostic", payload: ["phase": "webrtc_state", "result": "connected"])
          self.emitConnectedIfReady()
        case .failed, .closed:
          self.peerConnected = false
          self.finishCall(reason: "webrtc_\(state == .failed ? "failed" : "closed")", sendHangup: true)
        case .disconnected:
          self.peerConnected = false
          self.emit("diagnostic", payload: ["phase": "webrtc_disconnected"])
        default: break
        }
      }
    }
    rtc.onFailure = { [weak self] _ in
      DispatchQueue.main.async {
        self?.emit("error", payload: ["reason": "webrtc_operation_failed"])
      }
    }
  }

  func callKitDidActivate(_ audioSession: AVAudioSession) {
    RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
    RTCAudioSession.sharedInstance().isAudioEnabled = true
  }

  func callKitDidDeactivate(_ audioSession: AVAudioSession) {
    RTCAudioSession.sharedInstance().isAudioEnabled = false
    RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      guard let args = call.arguments as? [String: Any], let token = args["token"] as? String, !token.isEmpty else {
        result(FlutterError(code: "invalid_config", message: "Missing capability token", details: nil)); return
      }
      sessionID = "at-native-\(UUID().uuidString)"
      if let callID = args["incomingCallId"] as? String, !callID.isEmpty {
        incomingCallID = callID
      } else {
        incomingCallID = nil
      }
      pendingIncomingOffer = nil
      answerInProgress = false
      pendingAnswerResult = nil
      signaling.connect(gateway: args["gatewayUrl"] as? String, capabilityToken: token) { [weak self] outcome in
        DispatchQueue.main.async {
          guard let self else { return }
          switch outcome {
          case .success:
            self.emit("ready", payload: ["sessionId": self.sessionID ?? ""])
            result(["sessionId": self.sessionID ?? ""])
          case .failure(let error):
            result(FlutterError(code: "registration_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "dial":
      guard let args = call.arguments as? [String: Any],
            let number = args["phoneNumber"] as? String, !number.isEmpty,
            let sid = args["callSid"] as? String, !sid.isEmpty else {
        result(FlutterError(code: "invalid_call", message: "Missing outbound call identity or destination", details: nil)); return
      }
      guard callSid == nil else { result(FlutterError(code: "call_in_progress", message: "Native media already has an active call", details: nil)); return }
      callSid = sid
      connectedEmitted = false
      peerConnected = false
      callRequestSent = false
      pendingLocalCandidates.removeAll()
      rtc.makeOffer { [weak self] offer in
        DispatchQueue.main.async {
          guard let self else { return }
          switch offer {
          case .success(let jsep):
            self.signaling.sendCall(to: number, offer: jsep)
            self.callRequestSent = true
            self.pendingLocalCandidates.forEach { self.signaling.sendTrickle($0) }
            self.pendingLocalCandidates.removeAll()
            self.emit("ringing", payload: ["callSid": sid])
            result(["sessionId": self.sessionID ?? sid])
          case .failure(let error):
            self.finishCall(reason: "offer_failed", sendHangup: false)
            result(FlutterError(code: "webrtc_offer_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "answer":
      guard let args = call.arguments as? [String: Any],
            let requestedCallID = args["callSid"] as? String,
            requestedCallID == incomingCallID,
            requestedCallID == callSid,
            let offer = pendingIncomingOffer,
            !answerInProgress else {
        result(FlutterError(
          code: "incoming_call_unavailable",
          message: "No matching AT incoming offer is pending.",
          details: nil))
        return
      }
      answerInProgress = true
      pendingAnswerResult = result
      rtc.makeAnswer(for: offer) { [weak self] answer in
        DispatchQueue.main.async {
          guard let self, self.callSid == requestedCallID, self.answerInProgress else { return }
          self.answerInProgress = false
          let answerResult = self.pendingAnswerResult
          self.pendingAnswerResult = nil
          switch answer {
          case .success(let jsep):
            self.signaling.sendAccept(answer: jsep)
            self.emit("diagnostic", payload: ["phase": "incoming_answer", "result": "submitted"])
            self.callRequestSent = true
            self.pendingLocalCandidates.forEach { self.signaling.sendTrickle($0) }
            self.pendingLocalCandidates.removeAll()
            self.pendingIncomingOffer = nil
            self.connectionTimeout?.invalidate()
            self.connectionTimeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
              guard let self, self.callSid == requestedCallID, !self.connectedEmitted else { return }
              self.emit("processTerminated", payload: ["reason": "provider_media_timeout"])
              self.finishCall(reason: "media_connection_timeout", sendHangup: true)
            }
            answerResult?(nil)
          case .failure(let error):
            self.signaling.sendDecline()
            self.finishCall(reason: "answer_failed", sendHangup: false)
            answerResult?(FlutterError(
              code: "webrtc_answer_failed",
              message: error.localizedDescription,
              details: nil))
          }
        }
      }
    case "setMuted":
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
      rtc.setMuted(enabled)
      emit("micStatus", payload: ["muted": enabled])
      result(nil)
    case "setHeld":
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
      guard callSid != nil else {
        result(FlutterError(code: "no_active_call", message: "Hold requires an active call.", details: nil)); return
      }
      let request = enabled ? "hold" : "unhold"
      guard signaling.sendCallControl(request: request) else {
        result(FlutterError(code: "signaling_unavailable", message: "The AT signaling connection is not ready.", details: nil)); return
      }
      result(nil)
    case "sendDtmf":
      guard callSid != nil,
            let digit = (call.arguments as? [String: Any])?["digit"] as? String,
            digit.range(of: #"^[0-9*#]$"#, options: .regularExpression) != nil else {
        result(FlutterError(code: "invalid_dtmf", message: "DTMF requires an active call and one valid digit.", details: nil)); return
      }
      guard signaling.sendCallControl(request: "dtmf", fields: ["dtmf": ["tones": digit]]) else {
        result(FlutterError(code: "signaling_unavailable", message: "The AT signaling connection is not ready.", details: nil)); return
      }
      result(nil)
    case "end":
      finishCall(reason: "local_end", sendHangup: true)
      result(nil)
    case "dispose":
      finishCall(reason: "dispose", sendHangup: true)
      signaling.destroy()
      sessionID = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleSignaling(_ event: ATSignalingEvent) {
    if event.name == "incomingcall" {
      guard let incomingCallID else {
        emit("diagnostic", payload: [
          "phase": "incoming_offer_ignored",
          "result": "missing_call_identity_or_offer",
        ])
        return
      }
      if callSid == incomingCallID, pendingIncomingOffer != nil { return }
      guard callSid == nil,
            let offer = event.jsep,
            offer["type"] as? String == "offer",
            offer["sdp"] as? String != nil else {
        emit("error", payload: ["reason": "incoming_offer_missing_jsep"])
        return
      }
      pendingIncomingOffer = offer
      callSid = incomingCallID
      callAccepted = false
      connectedEmitted = false
      peerConnected = false
      callRequestSent = false
      answerInProgress = false
      pendingLocalCandidates.removeAll()
      emit("diagnostic", payload: ["phase": "incoming_offer", "result": "received"])
      emit("incoming", payload: ["callSid": incomingCallID])
      return
    }
    if event.name == "trickle", let candidate = event.payload["candidate"] as? [String: Any] {
      guard incomingCallID != nil || callSid != nil else { return }
      rtc.addRemoteCandidate(candidate)
      return
    }
    let shouldApplyRemoteJSEP = incomingCallID == nil || callRequestSent
    if shouldApplyRemoteJSEP,
       let jsep = event.jsep,
       ["progress", "accepted"].contains(event.name) {
      rtc.applyRemoteDescription(jsep) { [weak self] result in
        DispatchQueue.main.async {
          guard let self else { return }
          if case .failure = result { self.finishCall(reason: "remote_sdp_failed", sendHangup: true) }
          else { self.emitConnectedIfReady() }
        }
      }
    }
    switch event.name {
    case "calling", "progress": emit("ringing", payload: ["callSid": callSid ?? ""])
    case "accepted":
      callAccepted = true
      emit("diagnostic", payload: ["phase": "provider_call", "result": "accepted"])
      emitConnectedIfReady()
    case "hangup", "decline", "missed_call": finishCall(reason: event.name, sendHangup: false)
    case "registration_failed": emit("error", payload: ["reason": "registration_failed"])
    default: break
    }
  }

  private func emitConnectedIfReady() {
    guard callAccepted, peerConnected, !connectedEmitted, callSid != nil else { return }
    connectionTimeout?.invalidate()
    connectionTimeout = nil
    // The peer callback separately verifies ICE + DTLS connected; AT's
    // accepted event or SDP application alone does not mark media connected.
    // This flag is set only from the connection callback's connected path.
    connectedEmitted = true
    emit("connected", payload: ["callSid": callSid ?? ""])
  }

  private func finishCall(reason: String, sendHangup: Bool) {
    let hadProviderCall = callSid != nil || connectedEmitted
    guard hadProviderCall || incomingCallID != nil else { return }
    if sendHangup, hadProviderCall { signaling.sendHangup() }
    let answerResult = pendingAnswerResult
    pendingAnswerResult = nil
    connectionTimeout?.invalidate()
    connectionTimeout = nil
    rtc.closePeer()
    if hadProviderCall || incomingCallID != nil {
      emit("ended", payload: ["callSid": callSid ?? incomingCallID ?? "", "reason": reason])
    }
    answerResult?(FlutterError(
      code: "answer_cancelled",
      message: "The incoming media answer was cancelled.",
      details: nil))
    callSid = nil
    incomingCallID = nil
    pendingIncomingOffer = nil
    callAccepted = false
    connectedEmitted = false
    peerConnected = false
    callRequestSent = false
    answerInProgress = false
    pendingLocalCandidates.removeAll()
  }

  private func emit(_ method: String, payload: [String: Any]) {
    DispatchQueue.main.async { [channel] in channel.invokeMethod(method, arguments: payload) }
  }
}
