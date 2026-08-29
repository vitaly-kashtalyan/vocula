import Testing

@testable import VoculaKit

@Suite("Language policy")
struct LanguagePolicyTests {
  private func auto(_ codes: String...) -> LanguageSelection {
    LanguageSelection(codes: codes, autoDetect: true)
  }

  @Test("the larger probability among the selected languages wins")
  func largestWins() {
    #expect(
      LanguagePolicy.choose(
        probabilities: ["ru": 0.7, "en": 0.2],
        selection: auto("ru", "en")) == "ru")
    #expect(
      LanguagePolicy.choose(
        probabilities: ["ru": 0.1, "en": 0.6],
        selection: auto("ru", "en")) == "en")
    #expect(
      LanguagePolicy.choose(
        probabilities: ["de": 0.2, "fr": 0.5, "es": 0.1],
        selection: auto("de", "fr", "es")) == "fr")
  }

  @Test("an unselected language with the highest probability is ignored")
  func unselectedIgnored() {
    #expect(
      LanguagePolicy.choose(
        probabilities: ["uk": 0.9, "ru": 0.3, "en": 0.1],
        selection: auto("ru", "en")) == "ru")
  }

  @Test("auto-detect off uses the one selected language, whatever the probabilities")
  func pinWins() {
    let english = LanguageSelection(codes: ["en"], autoDetect: false)
    #expect(
      LanguagePolicy.choose(
        probabilities: ["ru": 0.9, "en": 0.05],
        selection: english) == "en")
  }

  @Test("with none of the selected languages scored the fallback is the first")
  func fallback() {
    #expect(
      LanguagePolicy.choose(
        probabilities: ["de": 0.9],
        selection: auto("ru", "en")) == "ru")
    #expect(
      LanguagePolicy.choose(
        probabilities: [:],
        selection: auto("en", "ru")) == "en")
  }

  @Test("an exact tie resolves to the earlier of the two deterministically")
  func tieIsDeterministic() {
    #expect(
      LanguagePolicy.choose(
        probabilities: ["ru": 0.5, "en": 0.5],
        selection: auto("ru", "en")) == "ru")
    #expect(
      LanguagePolicy.choose(
        probabilities: ["ru": 0.5, "en": 0.5],
        selection: auto("en", "ru")) == "en")
  }

  @Test("detection is needed only when more than one language can win")
  func needsDetection() {
    #expect(auto("ru", "en").needsDetection)
    #expect(!auto("ru").needsDetection)
    #expect(!LanguageSelection(codes: ["ru", "en"], autoDetect: false).needsDetection)
  }
}

@Suite("Language selection storage")
struct LanguageSelectionStorageTests {
  @Test("a stored list round-trips")
  func roundTrip() {
    let selection = LanguageSelection(stored: "ru,en,de", autoDetect: true)
    #expect(selection.codes == ["ru", "en", "de"])
    #expect(selection.stored == "ru,en,de")
  }

  @Test("blanks and empty fields are dropped")
  func tolerant() {
    #expect(LanguageSelection(stored: " ru , ,en,", autoDetect: true).codes == ["ru", "en"])
  }

  @Test("an empty or unusable stored value falls back to the default set")
  func neverEmpty() {
    #expect(
      LanguageSelection(stored: "", autoDetect: true).codes
        == LanguageSelection.default.codes)
    #expect(
      LanguageSelection(stored: " , ", autoDetect: false).codes
        == LanguageSelection.default.codes)
    #expect(
      LanguageSelection(codes: [], autoDetect: true).codes
        == LanguageSelection.default.codes)
  }

  @Test("duplicates are dropped, first occurrence wins")
  func deduplicated() {
    #expect(LanguageSelection(stored: "en,ru,en", autoDetect: true).codes == ["en", "ru"])
  }
}

@Suite("Language selection editing")
struct LanguageSelectionEditingTests {
  @Test("ticking an unselected language adds it, at the end")
  func addsAtTheEnd() {
    let selection = LanguageSelection(codes: ["ru", "en"], autoDetect: true)
    #expect(selection.toggling("de").codes == ["ru", "en", "de"])
  }

  @Test("ticking a selected language removes it")
  func removes() {
    let selection = LanguageSelection(codes: ["ru", "en"], autoDetect: true)
    #expect(selection.toggling("ru").codes == ["en"])
  }

  @Test("the last selected language cannot be unticked")
  func keepsTheLastOne() {
    let selection = LanguageSelection(codes: ["ru"], autoDetect: true)
    #expect(selection.toggling("ru") == selection)
  }

  @Test("with auto-detect off a tick pins that language and keeps the set")
  func pinsWhenAutoIsOff() {
    let selection = LanguageSelection(codes: ["ru", "en"], autoDetect: false)
    let after = selection.toggling("en")
    #expect(after.codes == ["ru", "en"])
    #expect(after.pinned == "en")
    #expect(after.autoDetect == false)
  }

  @Test("with auto-detect off a tick on an unselected language adds it and pins it")
  func pinsANewLanguage() {
    let selection = LanguageSelection(codes: ["ru"], autoDetect: false)
    let after = selection.toggling("de")
    #expect(after.codes == ["ru", "de"])
    #expect(after.pinned == "de")
  }

  @Test("turning auto-detect off keeps the whole set and pins the first language")
  func offKeepsTheSet() {
    let selection = LanguageSelection(codes: ["ru", "en", "de"], autoDetect: true)
    let after = selection.settingAutoDetect(false)
    #expect(after.codes == ["ru", "en", "de"])
    #expect(after.pinned == "ru")
    #expect(after.autoDetect == false)
  }

  @Test("turning auto-detect on changes nothing but the flag")
  func onKeepsTheSet() {
    let selection = LanguageSelection(codes: ["ru"], autoDetect: false)
    #expect(
      selection.settingAutoDetect(true)
        == LanguageSelection(
          codes: ["ru"],
          autoDetect: true))
  }
}
