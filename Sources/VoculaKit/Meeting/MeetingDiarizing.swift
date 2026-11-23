import Foundation

public protocol MeetingDiarizing: Sendable {
  func turns(in samples: [Int16]) async throws -> [SpeakerTurn]
}

public enum MeetingDiarizerError: Error, Equatable {
  case model(code: Int)
  case failed(code: Int)
}

public enum MeetingDiarizerParameters {
  public static func psi(from data: Data) throws -> [Double] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let tensors = root["tensors"] as? [String: Any],
      let psi = tensors["psi"] as? [String: Any],
      let base64 = psi["data_base64"] as? String,
      let bytes = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    else { throw MeetingDiarizerError.model(code: 0) }
    let count = bytes.count / MemoryLayout<Float>.size
    guard count > 0 else { throw MeetingDiarizerError.model(code: 0) }
    var floats = [Float](repeating: 0, count: count)
    _ = floats.withUnsafeMutableBytes { bytes.copyBytes(to: $0) }
    return floats.map(Double.init)
  }
}
