import Foundation

struct ATSignalingEvent {
  let name: String
  let payload: [String: Any]
  let jsep: [String: Any]?
}

enum ATSignalingError: LocalizedError {
  case invalidGateway
  case missingCapabilityToken
  case websocket(Error)
  case transportClosed
  case registrationFailed(String)
  case protocolError(String)
  case timeout(String)

  var errorDescription: String? {
    switch self {
    case .invalidGateway: return "The Africa's Talking gateway URL is invalid."
    case .missingCapabilityToken: return "The Africa's Talking capability token is missing."
    case .websocket(let error): return "Africa's Talking WebSocket failed: \(error.localizedDescription)"
    case .transportClosed: return "The Africa's Talking WebSocket closed."
    case .registrationFailed(let reason): return "Africa's Talking registration failed: \(reason)"
    case .protocolError(let reason): return "Africa's Talking protocol error: \(reason)"
    case .timeout(let phase): return "Timed out waiting for Africa's Talking \(phase)."
    }
  }
}
