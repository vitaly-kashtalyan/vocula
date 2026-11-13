import Testing

@testable import VoculaKit

@Suite("Engine fallback")
struct EngineFallbackTests {
  @Test("a selection on disk runs itself, whatever is ticked")
  func aReadySelectionRunsItself() {
    #expect(
      EngineFallback.running(selected: .parakeetUltra, languages: ["ja"], isReady: { _ in true })
        == .parakeetUltra)
  }

  @Test("a missing Ultra runs on Whisper while it downloads")
  func aMissingUltraRunsOnWhisper() {
    #expect(
      EngineFallback.running(
        selected: .parakeetUltra, languages: ["ru", "en"], isReady: { $0 == .largeV3Turbo })
        == .largeV3Turbo)
  }

  @Test("a missing Whisper runs on Parakeet when Parakeet hears every ticked language")
  func aMissingWhisperRunsOnParakeetWhenItHearsEverything() {
    #expect(
      EngineFallback.running(
        selected: .largeV3Turbo, languages: ["pl"], isReady: { $0 == .parakeetUltra })
        == .parakeetUltra)
  }

  @Test("Parakeet stands in for nobody who ticked a language it cannot hear")
  func parakeetIsNoFallbackForALanguageItCannotHear() {
    #expect(
      EngineFallback.running(
        selected: .largeV3Turbo, languages: ["pl", "ja"], isReady: { $0 == .parakeetUltra })
        == nil)
  }

  @Test("nothing on disk runs nothing")
  func nothingOnDiskRunsNothing() {
    #expect(
      EngineFallback.running(selected: .parakeetUltra, languages: ["en"], isReady: { _ in false })
        == nil)
  }

  @Test("the speech detector and the clean-up model never stand in for an engine")
  func onlyATranscriptionModelIsAFallback() {
    #expect(
      EngineFallback.running(
        selected: .largeV3Turbo, languages: ["en"],
        isReady: { $0 == .speechDetector || $0 == .qwenRefine2B })
        == nil)
  }

  @Test("a selected Ultra that will not load hands the selection to Whisper")
  func aDiscardedSelectedUltraHandsOverToWhisper() {
    #expect(
      EngineFallback.handOver(removed: .parakeetUltra, selected: .parakeetUltra) == .largeV3Turbo)
  }

  @Test("a fallback that will not load leaves the selection alone")
  func aDiscardedFallbackLeavesTheSelectionAlone() {
    #expect(EngineFallback.handOver(removed: .parakeetUltra, selected: .largeV3Turbo) == nil)
  }

  @Test("Whisper never hands over to itself")
  func whisperNeverHandsOverToItself() {
    #expect(EngineFallback.handOver(removed: .largeV3Turbo, selected: .largeV3Turbo) == nil)
  }

  @Test("a discarded clean-up model hands nothing over")
  func aDiscardedRefinerHandsOverNothing() {
    #expect(EngineFallback.handOver(removed: .qwenRefine2B, selected: .parakeetUltra) == nil)
  }
}
