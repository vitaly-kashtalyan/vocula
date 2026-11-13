import Testing

@testable import VoculaKit

@Suite("Engine default")
struct EngineDefaultTests {
  @Test("every language Parakeet hears chooses Ultra")
  func everyLanguageParakeetsChoosesUltra() {
    #expect(EngineDefault.choose(languages: ["en", "pl", "ru"]) == .parakeetUltra)
  }

  @Test("no languages at all chooses Ultra")
  func noLanguagesChoosesUltra() {
    #expect(EngineDefault.choose(languages: []) == .parakeetUltra)
  }

  @Test("one language Parakeet cannot hear chooses Whisper")
  func oneForeignLanguageChoosesWhisper() {
    #expect(EngineDefault.choose(languages: ["en", "ja"]) == .largeV3Turbo)
  }

  @Test("each system identifier is read as its base language, lowercased")
  func baseCodesReadTheLanguage() {
    #expect(
      EngineDefault.baseCodes(["en-US", "zh-Hans-CN", "EN-gb", "ru-PL"])
        == ["en", "zh", "en", "ru"])
  }

  @Test("an identifier with no language is dropped")
  func anEmptyIdentifierIsDropped() {
    #expect(EngineDefault.baseCodes(["", "pl-PL"]) == ["pl"])
  }
}
