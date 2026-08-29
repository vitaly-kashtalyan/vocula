import CryptoKit
import Foundation
import VoculaKit

enum LicenceVerifier {
  static let publicKeysBase64URL = [
    "ZxpFfC5Dbu6mtkc2O-I2TiDekag2oUwpt3TbdUK2Vic"
  ]

  enum Verdict: Equatable {
    case absent
    case licensed(holder: String)
    case invalid
  }

  static func verdict(
    for text: String,
    signedBy publicKeys: [String] = publicKeysBase64URL
  ) -> Verdict {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .absent }
    guard let key = LicenceKey(typed: text) else { return .invalid }
    for candidate in publicKeys {
      guard let publicKeyBytes = Data(base64URL: candidate),
        let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyBytes)
      else { continue }
      if publicKey.isValidSignature(key.signature, for: key.signedBytes) {
        return .licensed(holder: key.payload)
      }
    }
    return .invalid
  }
}
