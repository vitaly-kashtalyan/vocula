import Testing

@testable import VoculaKit

@Suite("Engine languages")
struct EngineLanguagesTests {
  @Test("Whisper is unrestricted")
  func whisperTakesAnything() {
    #expect(EngineLanguages.supports("ja", .whisper))
    #expect(EngineLanguages.supports("th", .whisper))
  }

  @Test("Parakeet covers the twenty-five European codes and nothing else")
  func parakeetIsRestricted() {
    #expect(EngineLanguages.supports("pl", .parakeet))
    #expect(EngineLanguages.supports("uk", .parakeet))
    #expect(!EngineLanguages.supports("ja", .parakeet))
    #expect(!EngineLanguages.supports("zh", .parakeet))
  }

  @Test("Narrowing drops unsupported codes and keeps the order of the rest")
  func narrowKeepsOrder() {
    let wide = LanguageSelection(codes: ["ru", "ja", "pl"], autoDetect: true)
    #expect(EngineLanguages.narrow(wide, to: .parakeet).codes == ["ru", "pl"])
  }

  @Test("Narrowing repairs a pinned language it just removed")
  func narrowRepairsPinned() {
    let pinnedToADroppedCode = LanguageSelection(
      codes: ["ru", "ja"], autoDetect: false, pinned: "ja")
    #expect(EngineLanguages.narrow(pinnedToADroppedCode, to: .parakeet).pinned == "ru")
  }

  @Test("Narrowing to Whisper changes nothing")
  func narrowIsIdentityForWhisper() {
    let wide = LanguageSelection(codes: ["ru", "ja", "pl"], autoDetect: true)
    #expect(EngineLanguages.narrow(wide, to: .whisper) == wide)
  }

  @Test("A selection with nothing left falls back rather than emptying")
  func narrowFallsBack() {
    let unsupported = LanguageSelection(codes: ["ja", "zh"], autoDetect: false, pinned: "ja")
    #expect(EngineLanguages.narrow(unsupported, to: .parakeet) == .default)
  }
}
