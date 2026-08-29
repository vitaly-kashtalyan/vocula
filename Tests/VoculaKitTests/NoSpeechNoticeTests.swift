import Testing

@testable import VoculaKit

@Suite("Telling the user nothing was heard")
struct NoSpeechNoticeTests {
  @Test("a short hold with nothing said is someone changing their mind")
  func shortHoldIsSilent() {
    #expect(!NoSpeechNotice.worthTelling(heldFor: .milliseconds(400)))
    #expect(!NoSpeechNotice.worthTelling(heldFor: .seconds(2)))
  }

  @Test("a long hold with nothing said is a question they cannot answer alone")
  func longHoldIsWorthTelling() {
    #expect(NoSpeechNotice.worthTelling(heldFor: NoSpeechNotice.worthTellingAfter))
    #expect(NoSpeechNotice.worthTelling(heldFor: .seconds(9)))
  }
}
