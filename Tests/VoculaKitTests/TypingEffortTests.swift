import Foundation
import Testing

@testable import VoculaKit

@Suite("Typing effort")
struct TypingEffortTests {
  @Test("a word is five characters, so 52 words a minute is 260 characters")
  func theRateIsCharactersNotWhitespaceWords() {
    #expect(TypingEffort.typingSeconds(characters: 260) == 60)
  }

  @Test("nothing typed is no time at all")
  func nothingCostsNothing() {
    #expect(TypingEffort.typingSeconds(characters: 0) == 0)
  }

  @Test("the rate is the one the citation states")
  func theRateIsPinned() {
    #expect(TypingEffort.wordsPerMinute == 52)
    #expect(TypingEffort.charactersPerWord == 5)
  }
}
