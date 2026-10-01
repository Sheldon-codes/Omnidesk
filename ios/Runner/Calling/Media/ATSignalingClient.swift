import Foundation
import CryptoKit
import os.log

/// Owns AT's Janus-compatible WebSocket signaling transport.
final class ATSignalingClient: NSObject {
  static let defaultGateway = "wss://webrtc.africastalking.com/connect"

  var onEvent: ((ATSignalingEvent) -> Void)?
  var onClosed: ((Error?) -> Void)?
  var onHandshake: ((String, String) -> Void)?

  private var socket: URLSessionWebSocketTask?
  private var session: URLSession?
  private var registrationCompletion: ((Result<Void, Error>) -> Void)?
  private var registrationTimeout: Timer?
  private var keepaliveTimer: Timer?
  private var isRegistered = false
  private var hasCreatedHandle = false
  private var isClosing = false
  private var connectionGeneration: UInt64 = 0
  private var connectedEndpoint: String?
  private var capabilityFingerprint: Data?
  private let logger = Logger(subsystem: "com.bigbrainzsolutions.omnidesk", category: "ATSignaling")

  func connect(
    gateway: String?,
    capabilityToken: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard !capabilityToken.isEmpty else {
      completion(.failure(ATSignalingError.missingCapabilityToken))
      return
    }
    let endpoint = gateway?.isEmpty == false ? gateway! : Self.defaultGateway
    guard let url = URL(string: endpoint), url.scheme == "wss", url.host != nil else {
      completion(.failure(ATSignalingError.invalidGateway))
      return
    }

    let fingerprint = Data(SHA256.hash(data: Data(capabilityToken.utf8)))
    if isRegistered, connectedEndpoint == endpoint, capabilityFingerprint == fingerprint {
      onHandshake?("at-protocol", "registration_reused")
      completion(.success(()))
      return
    }

    close()
    isClosing = false
    connectedEndpoint = endpoint
    capabilityFingerprint = fingerprint
    let generation = connectionGeneration
    registrationCompletion = completion
    registrationTimeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
      guard let self, self.connectionGeneration == generation,
            let completion = self.registrationCompletion else { return }
      self.registrationCompletion = nil
      self.close()
      completion(.failure(ATSignalingError.timeout("registration")))
    }
    let configuration = URLSessionConfiguration.ephemeral
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    // URLSessionWebSocketTask serializes these as the Sec-WebSocket-Protocol
    // values. The token is never included in diagnostics or errors.
    socket = session?.webSocketTask(with: url, protocols: ["at-protocol", capabilityToken])
    socket?.resume()
    receiveNext(generation: generation)
  }

  func send(request: String, fields: [String: Any] = [:], jsep: [String: Any]? = nil) {
    guard hasCreatedHandle else { return }
    var body: [String: Any] = ["request": request]
    fields.forEach { body[$0.key] = $0.value }
    var message: [String: Any] = ["command": "message", "body": body]
    if let jsep { message["jsep"] = jsep }
    sendJSON(message)
  }

  func sendKeepalive() {
    guard hasCreatedHandle else { return }
    sendJSON(["command": "keepalive"])
  }

  func sendCall(to number: String, offer: [String: Any]) {
    send(request: "call", fields: ["to": number], jsep: offer)
  }

  func sendAccept(answer: [String: Any]) {
    send(request: "accept", jsep: answer)
  }

  func sendDecline() {
    send(request: "decline")
  }

  func sendTrickle(_ candidate: [String: Any]?) {
    sendJSON(["command": "trickle", "candidate": candidate ?? ["completed": true]])
  }

  func sendHangup() { send(request: "hangup") }

  func destroy() {
    guard hasCreatedHandle, let socket,
          let data = try? JSONSerialization.data(withJSONObject: ["command": "destroy"]),
          let text = String(data: data, encoding: .utf8) else {
      close()
      return
    }
    let generation = connectionGeneration
    socket.send(.string(text)) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.connectionGeneration == generation else { return }
        self.close()
      }
    }
  }

  func close() {
    isClosing = true
    connectionGeneration &+= 1
    registrationTimeout?.invalidate()
    registrationTimeout = nil
    keepaliveTimer?.invalidate()
    keepaliveTimer = nil
    socket?.cancel(with: .normalClosure, reason: nil)
    socket = nil
    session?.invalidateAndCancel()
    session = nil
    isRegistered = false
    hasCreatedHandle = false
    connectedEndpoint = nil
    capabilityFingerprint = nil
    registrationCompletion = nil
  }

  private func createSession() {
    sendJSON(["command": "create"])
  }

  private func register() {
    guard hasCreatedHandle else { return }
    logger.info("AT gateway result=register_sent")
    onHandshake?("at-protocol", "register_sent")
    send(request: "register")
  }

  private func sendJSON(_ value: [String: Any]) {
    guard let socket, JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          let text = String(data: data, encoding: .utf8) else { return }
    let generation = connectionGeneration
    socket.send(.string(text)) { [weak self] error in
      guard let error, let self else { return }
      DispatchQueue.main.async {
        self.failTransport(error, generation: generation)
      }
    }
  }

  private func receiveNext(generation: UInt64) {
    guard connectionGeneration == generation else { return }
    guard let socket, !isClosing else { return }
    socket.receive { [weak self] result in
      guard let self else { return }
      guard self.connectionGeneration == generation, !self.isClosing else { return }
      switch result {
      case .success(.string(let text)):
        self.handle(text: text)
        self.receiveNext(generation: generation)
      case .success(.data(let data)):
        if let text = String(data: data, encoding: .utf8) {
          self.handle(text: text)
        }
        self.receiveNext(generation: generation)
      case .success:
        self.receiveNext(generation: generation)
      case .failure(let error):
        self.failTransport(error, generation: generation)
      }
    }
  }

  /// Retire a transport exactly once. URLSession can complete pending send and
  /// receive operations with the same close error; generation invalidation
  /// makes the first failure authoritative and suppresses the rest.
  private func failTransport(_ error: Error, generation: UInt64) {
    guard connectionGeneration == generation, !isClosing else { return }
    let completion = registrationCompletion
    registrationCompletion = nil
    close()
    completion?(.failure(ATSignalingError.websocket(error)))
    onClosed?(error)
  }

  private func handle(text: String) {
    guard let data = text.data(using: .utf8),
          let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return }

    let response = value["response"] as? String
    if response == "success", !hasCreatedHandle {
      hasCreatedHandle = true
      onHandshake?("at-protocol", "session_created")
      logger.info("AT gateway result=session_created")
      register()
      return
    }
    if response == "offline" {
      registrationCompletion = nil
      onEvent?(ATSignalingEvent(name: "offline", payload: value, jsep: nil))
      return
    }
    if response == "closed" {
      let completion = registrationCompletion
      registrationCompletion = nil
      close()
      completion?(.failure(ATSignalingError.transportClosed))
      onClosed?(nil)
      return
    }
    if response == "trickle" {
      onEvent?(ATSignalingEvent(name: "trickle", payload: value, jsep: nil))
      return
    }

    guard response == "event", let eventdata = value["eventdata"] as? [String: Any],
          let result = eventdata["result"] as? [String: Any],
          let event = result["event"] as? String else { return }

    let jsep = value["jsep"] as? [String: Any]
    switch event {
    case "registered":
      isRegistered = true
      registrationTimeout?.invalidate()
      registrationTimeout = nil
      keepaliveTimer?.invalidate()
      let generation = connectionGeneration
      keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
        guard let self, self.connectionGeneration == generation, self.isRegistered else { return }
        self.sendKeepalive()
      }
      onHandshake?("at-protocol", "registered")
      logger.info("AT gateway result=registered")
      registrationCompletion?(.success(()))
      registrationCompletion = nil
    case "registration_failed":
      let reason = "\(result["code"] ?? "unknown") \(result["reason"] ?? "")".trimmingCharacters(in: .whitespaces)
      let completion = registrationCompletion
      registrationCompletion = nil
      close()
      completion?(.failure(ATSignalingError.registrationFailed(reason)))
    default:
      break
    }
    onEvent?(ATSignalingEvent(name: event, payload: result, jsep: jsep))
  }
}

extension ATSignalingClient: URLSessionWebSocketDelegate {
  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    guard !isClosing, webSocketTask === socket else { return }
    // The selected protocol might be the capability token on a broken server;
    // only emit the known-safe protocol label.
    let safeProtocol = `protocol` == "at-protocol" ? "at-protocol" : "other_or_none"
    logger.info("WebSocket negotiatedProtocol=\(safeProtocol, privacy: .public) result=opened")
    onHandshake?(safeProtocol, "opened")
    createSession()
  }
}
