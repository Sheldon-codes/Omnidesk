import Foundation
import WebRTC

/// A single audio-only native peer connection. ICE is intentionally empty:
/// the inspected AT client receives no servers from OmniDesk and defines no
/// gateway/default server provisioning path.
final class ATWebRTCSession: NSObject {
  var onLocalCandidate: (([String: Any]?) -> Void)?
  var onConnectionState: ((RTCPeerConnectionState) -> Void)?
  var onFailure: ((Error) -> Void)?

  private let factory: RTCPeerConnectionFactory
  private var peer: RTCPeerConnection?
  private var localTrack: RTCAudioTrack?
  private var pendingRemoteCandidates: [RTCIceCandidate] = []
  private var hasRemoteDescription = false
  private var sentEndOfCandidates = false

  override init() {
    RTCInitializeSSL()
    let encoder = RTCDefaultVideoEncoderFactory()
    let decoder = RTCDefaultVideoDecoderFactory()
    factory = RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
    super.init()
  }

  func makeOffer(completion: @escaping (Result<[String: Any], Error>) -> Void) {
    closePeer()
    let configuration = RTCConfiguration()
    configuration.iceServers = []
    configuration.bundlePolicy = .balanced
    configuration.rtcpMuxPolicy = .require
    configuration.sdpSemantics = .unifiedPlan
    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    guard let peer = factory.peerConnection(with: configuration, constraints: constraints, delegate: self) else {
      completion(.failure(ATSignalingError.protocolError("Unable to create peer connection.")))
      return
    }
    self.peer = peer
    let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
    let track = factory.audioTrack(with: audioSource, trackId: "at-audio")
    localTrack = track
    guard peer.add(track, streamIds: ["at-audio-stream"]) != nil else {
      closePeer()
      completion(.failure(ATSignalingError.protocolError("Unable to add local audio track.")))
      return
    }

    let offerConstraints = RTCMediaConstraints(
      mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)
    peer.offer(for: offerConstraints) { [weak peer] description, error in
      guard let peer, let description, error == nil else {
        completion(.failure(error ?? ATSignalingError.protocolError("WebRTC offer creation failed.")))
        return
      }
      peer.setLocalDescription(description) { error in
        guard error == nil else {
          completion(.failure(error ?? ATSignalingError.protocolError("Setting local SDP failed.")))
          return
        }
        completion(.success(["type": "offer", "sdp": description.sdp]))
      }
    }
  }

  func applyRemoteDescription(_ jsep: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
    guard let type = jsep["type"] as? String, let sdp = jsep["sdp"] as? String,
          let peer else {
      completion(.failure(ATSignalingError.protocolError("Invalid remote JSEP description.")))
      return
    }
    let sdpType: RTCSdpType
    switch type {
    case "offer": sdpType = .offer
    case "answer": sdpType = .answer
    case "pranswer": sdpType = .prAnswer
    default:
      completion(.failure(ATSignalingError.protocolError("Unsupported remote JSEP type.")))
      return
    }
    peer.setRemoteDescription(RTCSessionDescription(type: sdpType, sdp: sdp)) { [weak self] error in
      guard let self, error == nil else {
        completion(.failure(error ?? ATSignalingError.protocolError("Setting remote SDP failed.")))
        return
      }
      self.hasRemoteDescription = true
      let buffered = self.pendingRemoteCandidates
      self.pendingRemoteCandidates.removeAll()
      self.addCandidates(buffered, completion: completion)
    }
  }

  func addRemoteCandidate(_ json: [String: Any]) {
    guard let peer else { return }
    if json["completed"] as? Bool == true {
      peer.add(RTCIceCandidate(sdp: "", sdpMLineIndex: 0, sdpMid: "audio")) { [weak self] error in
        if let error { self?.onFailure?(error) }
      }
      return
    }
    guard let sdp = json["candidate"] as? String,
          let mid = json["sdpMid"] as? String,
          let line = (json["sdpMLineIndex"] as? NSNumber)?.int32Value else { return }
    let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: line, sdpMid: mid)
    guard hasRemoteDescription else {
      pendingRemoteCandidates.append(candidate)
      return
    }
    peer.add(candidate) { [weak self] error in
      if let error { self?.onFailure?(error) }
    }
  }

  func setMuted(_ muted: Bool) { localTrack?.isEnabled = !muted }

  func closePeer() {
    peer?.delegate = nil
    peer?.close()
    peer = nil
    localTrack = nil
    pendingRemoteCandidates.removeAll()
    hasRemoteDescription = false
    sentEndOfCandidates = false
  }

  private func addCandidates(_ candidates: [RTCIceCandidate], completion: @escaping (Result<Void, Error>) -> Void) {
    guard let peer else { completion(.success(())); return }
    let group = DispatchGroup()
    let lock = NSLock()
    var failure: Error?
    for candidate in candidates {
      group.enter()
      peer.add(candidate) { error in
        if let error {
          lock.lock()
          if failure == nil { failure = error }
          lock.unlock()
        }
        group.leave()
      }
    }
    group.notify(queue: .main) {
      if let failure { completion(.failure(failure)) } else { completion(.success(())) }
    }
  }
}

extension ATWebRTCSession: RTCPeerConnectionDelegate {
  func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCPeerConnectionState) {
    onConnectionState?(state)
  }
  func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
    onLocalCandidate?(["candidate": candidate.sdp, "sdpMid": candidate.sdpMid ?? "audio", "sdpMLineIndex": Int(candidate.sdpMLineIndex)])
  }
  func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
  func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
  func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
  func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
  func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
  func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
  func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
  func peerConnection(_ peerConnection: RTCPeerConnection, didChange gatheringState: RTCIceGatheringState) {
    if gatheringState == .complete, !sentEndOfCandidates {
      sentEndOfCandidates = true
      onLocalCandidate?(nil)
    }
  }
  func peerConnection(_ peerConnection: RTCPeerConnection, didAdd receiver: RTCRtpReceiver, streams: [RTCMediaStream]) {}
  func peerConnection(_ peerConnection: RTCPeerConnection, didChangeStandardizedIceConnectionState state: RTCIceConnectionState) {}
}
