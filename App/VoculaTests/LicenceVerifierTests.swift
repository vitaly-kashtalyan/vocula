import CryptoKit
import Foundation
import Testing

@testable import Vocula
@testable import VoculaKit

@Suite("Licence verification")
struct LicenceVerifierTests {
  private struct Signer {
    let key = Curve25519.Signing.PrivateKey()
    var publicKey: String { key.publicKey.rawRepresentation.base64URL }
    func licence(for holder: String) -> String {
      let payload = Data(holder.utf8)
      let signature = try! key.signature(for: payload)
      return "\(payload.base64URL).\(signature.base64URL)"
    }
  }

  @Test("a key we signed names its holder")
  func genuine() {
    let signer = Signer()
    #expect(
      LicenceVerifier.verdict(
        for: signer.licence(for: "buyer@example.com"),
        signedBy: [signer.publicKey])
        == .licensed(holder: "buyer@example.com"))
  }

  @Test("a key whose holder was edited is refused")
  func tampered() {
    let signer = Signer()
    let genuine = signer.licence(for: "buyer@example.com")
    let signature = genuine.split(separator: ".")[1]
    let forged = "\(Data("someone.else@example.com".utf8).base64URL).\(signature)"
    #expect(LicenceVerifier.verdict(for: forged, signedBy: [signer.publicKey]) == .invalid)
  }

  @Test("a key signed by another pair is refused")
  func wrongSigner() {
    let theirs = Signer()
    let ours = Signer()
    #expect(
      LicenceVerifier.verdict(
        for: theirs.licence(for: "buyer@example.com"),
        signedBy: [ours.publicKey]) == .invalid)
  }

  @Test("blank input is absent, not invalid", arguments: ["", "   ", "\n\t "])
  func blank(_ text: String) {
    #expect(LicenceVerifier.verdict(for: text) == .absent)
  }

  @Test("nonsense is invalid")
  func nonsense() {
    #expect(LicenceVerifier.verdict(for: "not-a-key") == .invalid)
  }

  @Test("a licence signed by a retired key keeps working while that key is listed")
  func rotation() {
    let retired = Signer()
    let current = Signer()
    let sold = retired.licence(for: "buyer@example.com")
    #expect(
      LicenceVerifier.verdict(
        for: sold,
        signedBy: [current.publicKey, retired.publicKey])
        == .licensed(holder: "buyer@example.com"))
  }

  @Test("dropping a key is what revokes the licences signed under it")
  func revocation() {
    let retired = Signer()
    let current = Signer()
    let sold = retired.licence(for: "buyer@example.com")
    #expect(LicenceVerifier.verdict(for: sold, signedBy: [current.publicKey]) == .invalid)
  }

  @Test("every embedded public key is a usable Ed25519 key, and there is at least one")
  func embeddedKeys() throws {
    #expect(!LicenceVerifier.publicKeysBase64URL.isEmpty)
    for candidate in LicenceVerifier.publicKeysBase64URL {
      let bytes = try #require(Data(base64URL: candidate))
      #expect(bytes.count == 32)
      #expect(throws: Never.self) {
        try Curve25519.Signing.PublicKey(rawRepresentation: bytes)
      }
    }
  }

  @Test("the minting key is the one this build was released with")
  func mintingKeyIsPinned() {
    #expect(
      LicenceVerifier.publicKeysBase64URL.first
        == "ZxpFfC5Dbu6mtkc2O-I2TiDekag2oUwpt3TbdUK2Vic")
  }

  @Test("the development key that never minted a sale is gone, and stays gone")
  func developmentKeyIsRetired() {
    #expect(
      !LicenceVerifier.publicKeysBase64URL
        .contains("xGLJYc_j53nWe87bZDQCiZMYTcWvS_91Vs-ghSh620I"))
  }
}
