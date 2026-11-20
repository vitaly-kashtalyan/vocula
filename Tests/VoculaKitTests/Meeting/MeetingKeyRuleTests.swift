import Testing

@testable import VoculaKit

@Suite struct MeetingKeyRuleTests {
  @Test func anExistingKeyIsUsed() {
    #expect(MeetingKeyRule.step(afterLookup: 0, keyByteCount: 32, mayMint: true) == .use)
  }

  @Test func onlyAMissingItemMints() {
    #expect(MeetingKeyRule.step(afterLookup: -25300, keyByteCount: nil, mayMint: true) == .mint)
  }

  @Test func aLockedKeychainNeverMints() {
    #expect(
      MeetingKeyRule.step(afterLookup: -25308, keyByteCount: nil, mayMint: true)
        == .refuse(code: -25308))
    #expect(
      MeetingKeyRule.step(afterLookup: -128, keyByteCount: nil, mayMint: true)
        == .refuse(code: -128))
  }

  @Test func aMalformedKeyNeverMints() {
    #expect(
      MeetingKeyRule.step(afterLookup: 0, keyByteCount: 16, mayMint: true) == .refuse(code: 0))
    #expect(
      MeetingKeyRule.step(afterLookup: 0, keyByteCount: nil, mayMint: true) == .refuse(code: 0))
  }

  @Test func aMissingKeyIsNotMintedWhenMintingIsOff() {
    #expect(
      MeetingKeyRule.step(afterLookup: -25300, keyByteCount: nil, mayMint: false)
        == .refuse(code: -25300))
    #expect(MeetingKeyRule.step(afterLookup: 0, keyByteCount: 32, mayMint: false) == .use)
  }
}
