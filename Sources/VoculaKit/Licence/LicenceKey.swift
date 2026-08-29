import Foundation

public struct LicenceKey: Equatable, Sendable {
  public let payload: String
  public let signature: Data

  public init?(typed text: String) {
    let compact = text.filter { !$0.isWhitespace }
    let parts = compact.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2,
      let payloadData = Data(base64URL: String(parts[0])),
      let payload = String(data: payloadData, encoding: .utf8),
      !payload.isEmpty,
      let signature = Data(base64URL: String(parts[1])),
      !signature.isEmpty
    else { return nil }
    self.payload = payload
    self.signature = signature
  }

  public var signedBytes: Data { Data(payload.utf8) }
}

extension Data {
  public init?(base64URL text: String) {
    var s = text.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    switch s.count % 4 {
    case 0: break
    case 2: s += "=="
    case 3: s += "="
    default: return nil
    }
    guard let data = Data(base64Encoded: s) else { return nil }
    self = data
  }

  public var base64URL: String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
