import Foundation
import Testing
import VoculaKit
import VoculaWhisper

@Suite("Whisper language catalog")
struct WhisperLanguagesTests {
  @Test("the catalog is populated and names languages in English")
  func populated() {
    #expect(WhisperLanguages.all.count > 90)
    #expect(WhisperLanguages.language(for: "es")?.name == "Spanish")
    #expect(WhisperLanguages.language(for: "en")?.name == "English")
  }

  @Test("a language shows its own name, and English does not show it twice")
  func nativeNames() {
    #expect(WhisperLanguages.language(for: "es")?.nativeName == "Español")
    #expect(WhisperLanguages.language(for: "en")?.nativeName == nil)
  }

  @Test("codes are unique and never whisper's own \u{201c}auto\u{201d}")
  func codes() {
    let codes = WhisperLanguages.all.map(\.code)
    #expect(Set(codes).count == codes.count)
    #expect(!codes.contains("auto"))
  }

  @Test("an unknown code degrades to itself rather than vanishing")
  func unknownCode() {
    #expect(WhisperLanguages.language(for: "zz") == nil)
    #expect(WhisperLanguages.name(for: "zz") == "ZZ")
  }

  @Test("the list is sorted by English name, which is what the picker shows")
  func sorted() {
    let names = WhisperLanguages.all.map(\.name)
    #expect(
      names
        == names.sorted {
          $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        })
  }
}

@Suite("A language has a name to show and a name to search")
struct WhisperLanguageNamesTests {
  private func language(_ code: String) throws -> WhisperLanguage {
    try #require(WhisperLanguages.language(for: code))
  }

  @Test("the English name survives for the search corpus")
  func englishNameIsKept() throws {
    #expect(try language("de").name == "German")
    #expect(try language("ru").name == "Russian")
  }

  @Test("the shown name and the searched name are separate fields")
  func twoFieldsExist() throws {
    let german = try language("de")
    #expect(!german.displayName.isEmpty)
    #expect(!german.name.isEmpty)
  }

  @Test("under an English interface the shown name is the English one")
  func englishInterfaceShowsEnglish() throws {
    try #require(Locale.interface.identifier.hasPrefix("en"))
    for language in WhisperLanguages.all {
      #expect(language.displayName == language.name)
    }
  }

  @Test("the native name is dropped only when it repeats what is shown")
  func nativeNameIsNotRedundant() throws {
    #expect(try language("en").nativeName == nil)
    #expect(try language("ru").nativeName == "Русский")
  }
}
