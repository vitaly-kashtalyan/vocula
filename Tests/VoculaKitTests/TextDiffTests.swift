import Testing

@testable import VoculaKit

@Suite("Word diff")
struct TextDiffTests {
  @Test("identical text is one unchanged run")
  func identicalIsOneRun() {
    #expect(
      TextDiff.words(from: "два слова здесь", to: "два слова здесь") == [.same("два слова здесь")])
  }

  @Test("a replaced word shows as removed then added")
  func replacementShowsBothSides() {
    #expect(
      TextDiff.words(from: "он переключает автоматически", to: "он переключался автоматически")
        == [.same("он"), .removed("переключает"), .added("переключался"), .same("автоматически")])
  }

  @Test("neighbouring words of one kind read as a phrase")
  func neighboursJoin() {
    #expect(
      TextDiff.words(from: "ну вот значит на сервере работает", to: "на сервере работает")
        == [.removed("ну вот значит"), .same("на сервере работает")])
  }

  @Test("an insertion at the end is kept")
  func insertionAtTheEnd() {
    #expect(
      TextDiff.words(from: "это работает", to: "это работает хорошо")
        == [.same("это работает"), .added("хорошо")])
  }

  @Test("empty on either side is not a crash")
  func emptySides() {
    #expect(TextDiff.words(from: "", to: "слово") == [.added("слово")])
    #expect(TextDiff.words(from: "слово", to: "") == [.removed("слово")])
    #expect(TextDiff.words(from: "", to: "").isEmpty)
  }
}
