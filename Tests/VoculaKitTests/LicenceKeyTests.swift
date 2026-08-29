import Foundation
import Testing

@testable import VoculaKit

@Suite("Licence key format")
struct LicenceKeyTests {
  private func key(payload: String, signature: Data) -> String {
    "\(Data(payload.utf8).base64URL).\(signature.base64URL)"
  }

  private let signature = Data((0..<64).map { UInt8($0) })

  @Test("a well-formed key round-trips")
  func roundTrip() throws {
    let parsed = try #require(
      LicenceKey(typed: key(payload: "buyer@example.com", signature: signature)))
    #expect(parsed.payload == "buyer@example.com")
    #expect(parsed.signature == signature)
    #expect(parsed.signedBytes == Data("buyer@example.com".utf8))
  }

  @Test("whitespace anywhere is ignored, not just at the ends")
  func whitespace() throws {
    let text = key(payload: "buyer@example.com", signature: signature)
    let wrapped = "  " + text.prefix(20) + "\n  " + text.dropFirst(20) + " \t\n"
    let parsed = try #require(LicenceKey(typed: String(wrapped)))
    #expect(parsed.payload == "buyer@example.com")
    #expect(parsed.signature == signature)
  }

  @Test(
    "malformed keys are refused",
    arguments: [
      "", "no-separator", "a.b.c", ".", "aGk.", ".aGk", "!!!.aGk", "aGk.!!!", "a.aGk",
    ])
  func malformed(_ text: String) {
    #expect(LicenceKey(typed: text) == nil)
  }

  @Test("base64url carries bytes that plain base64 would spell with + and /")
  func alphabet() throws {
    let awkward = Data([0xFB, 0xFF, 0xBE, 0x00])
    #expect(
      awkward.base64EncodedString().contains("+")
        || awkward.base64EncodedString().contains("/"))
    #expect(!awkward.base64URL.contains("+"))
    #expect(!awkward.base64URL.contains("/"))
    #expect(!awkward.base64URL.contains("="))
    #expect(Data(base64URL: awkward.base64URL) == awkward)
  }
}
