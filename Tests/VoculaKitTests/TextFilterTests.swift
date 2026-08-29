import Testing

@testable import VoculaKit

@Suite("TextFilter")
struct TextFilterTests {
  @Test(
    "a whole-text stop phrase is dropped as a hallucination",
    arguments: [
      "Thanks for watching...",
      "thank you for watching…",
      "  Subscribe to my channel  ",
      "Thanks For Watching",
      "Thanks for watching!",
    ])
  func stopPhraseDropsTheWholeText(text: String) {
    let result = TextFilter().evaluate(text, language: "en")
    #expect(result.wasDroppedAsHallucination == true)
    #expect(result.text.isEmpty)
  }

  @Test("ordinary text is untouched")
  func ordinaryTextSurvives() {
    let result = TextFilter()
      .evaluate("Hay que reescribir el controlador", language: "en")
    #expect(result.wasDroppedAsHallucination == false)
    #expect(result.text == "Hay que reescribir el controlador")
  }

  @Test("a legitimate one-word dictation is not treated as a stop phrase")
  func ordinaryOneWordSurvives() {
    let filter = TextFilter()
    #expect(filter.filter("you", language: "en") == "you")
    #expect(filter.filter("bye", language: "en") == "bye")
  }

  @Test("a stop phrase inside a longer real sentence does not drop it")
  func substringDoesNotDrop() {
    let result = TextFilter()
      .evaluate("He said thanks for watching and laughed", language: "en")
    #expect(result.wasDroppedAsHallucination == false)
  }

  @Test(
    "a whole-output sound-event tag is dropped as a hallucination",
    arguments: [
      "*sad music*",
      "[Music]",
      "[BLANK_AUDIO]",
      "(laughs)",
      "♪♪♪",
      "♪ lalala ♪",
      "[música]",
      "  [Music].  ",
      "[Music] [Music]",
    ])
  func soundEventTagDropsTheWholeText(text: String) {
    let result = TextFilter().evaluate(text, language: "en")
    #expect(result.wasDroppedAsHallucination == true)
    #expect(result.text.isEmpty)
  }

  @Test(
    "brackets and asterisks inside real text survive",
    arguments: [
      "pon un asterisco *",
      "*bold* and *italic*",
      "dijo (en voz baja) algo",
      "see [Music] in the tracklist",
      "paréntesis de apertura (",
      "array[0] = 1",
      "(a) then (b) matter",
    ])
  func delimitersInsideRealTextSurvive(text: String) {
    let result = TextFilter().evaluate(text, language: "en")
    #expect(result.wasDroppedAsHallucination == false)
    #expect(result.text == text)
  }

  @Test(
    "short generic near-silence hallucinations are deliberately not filtered",
    arguments: ["Thank you.", "Okay.", "so", "Gracias."])
  func shortGenericPhrasesAreNotFiltered(text: String) {
    let result = TextFilter().evaluate(text, language: "en")
    #expect(result.wasDroppedAsHallucination == false)
    #expect(result.text == text)
  }

  @Test("filtering runs before refining, so the dictionary is never lost on fallback")
  func filterIsIdempotent() {
    let filter = TextFilter(stopPhrases: [:])
    let once = filter.filter("swift", language: "en")
    #expect(filter.filter(once, language: "en") == once)
  }

  @Test("empty input stays empty")
  func emptyInput() {
    #expect(TextFilter().filter("", language: "en") == "")
  }
}

@Suite("Stop phrases follow the recognition language")
struct StopPhraseLanguageTests {
  private let filter = TextFilter()

  @Test("a French artefact is dropped in French")
  func frenchIsFilteredInFrench() {
    #expect(
      filter.evaluate("Sous-titrage Société Radio-Canada", language: "fr")
        .wasDroppedAsHallucination)
  }

  @Test("the same artefact is NOT dropped when whisper worked in English")
  func frenchSurvivesInEnglish() {
    #expect(
      filter.evaluate("Sous-titrage Société Radio-Canada", language: "en")
        .wasDroppedAsHallucination == false)
  }

  @Test(
    "a short courtesy is never filtered, in any language",
    arguments: [
      ("es", "Gracias."), ("de", "Vielen Dank."), ("it", "Grazie."),
      ("pt", "Obrigado."), ("uk", "Дякую."), ("pl", "Dziękuję."),
      ("en", "Thank you."),
    ])
  func courtesiesSurvive(language: String, text: String) {
    #expect(filter.evaluate(text, language: language).wasDroppedAsHallucination == false)
  }

  @Test(
    "English is always in play, whatever the language",
    arguments: ["de", "ru", "pl", "uk", nil])
  func englishAlwaysApplies(language: String?) {
    #expect(
      filter.evaluate("Thanks for watching", language: language)
        .wasDroppedAsHallucination)
  }

  @Test("whisper's bare language code is what selects the list")
  func bareCodeSelects() {
    #expect(
      filter.evaluate("Дякую за перегляд", language: "uk")
        .wasDroppedAsHallucination)
    #expect(StopPhrases.forLanguage("uk-UA") == StopPhrases.english)
    #expect(StopPhrases.forLanguage("pt-BR") == StopPhrases.english)
  }

  @Test(
    "a language with a measured artefact gets it, on top of English",
    arguments: ["fr", "uk", "ru"])
  func measuredLanguagesHavePhrases(language: String) {
    let own = StopPhrases.byLanguage[language]
    #expect(own?.isEmpty == false, "\(language) has no stop phrases")
    #expect(
      StopPhrases.forLanguage(language).count
        == (own?.count ?? 0) + StopPhrases.english.count)
  }

  @Test("every phrase is specific enough that nobody dictates it by accident")
  func everyPhraseIsSpecific() {
    for (language, phrases) in StopPhrases.byLanguage {
      for phrase in phrases {
        #expect(
          phrase.contains(" "),
          "\(language): “\(phrase)” is one word — too close to real dictation")
        #expect(
          phrase.count >= 15,
          "\(language): “\(phrase)” is \(phrase.count) characters — too short")
      }
    }
  }

  @Test("an unknown language still gets the measured English list")
  func unknownFallsBackToEnglish() {
    #expect(StopPhrases.forLanguage("xx") == StopPhrases.english)
    #expect(StopPhrases.forLanguage(nil) == StopPhrases.english)
  }

  @Test("every seeded phrase is stored in the form the filter compares")
  func phrasesAreNormalised() {
    for (language, phrases) in StopPhrases.byLanguage {
      for phrase in phrases {
        #expect(
          phrase == phrase.lowercased(),
          "\(language): “\(phrase)” is not lower-cased and would never match")
        #expect(phrase == phrase.trimmingCharacters(in: .whitespacesAndNewlines))
      }
    }
  }
}
