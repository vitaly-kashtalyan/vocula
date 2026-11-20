import Testing

@testable import VoculaKit

@Suite struct MeetingModelTests {
  private let english = LanguageSelection(codes: ["en"], autoDetect: true)

  @Test func onlyATranscriptionModelTranscribes() {
    #expect(MeetingModel(model: .largeV3Turbo, languages: english) != nil)
    #expect(MeetingModel(model: .parakeetUltra, languages: english)?.family == .parakeet)
    #expect(MeetingModel(model: .speechDetector, languages: english) == nil)
    #expect(MeetingModel(model: .qwenRefine2B, languages: english) == nil)
  }

  @Test func theSelectedModelWinsWhenReady() {
    let chosen = MeetingModel.choose(selected: .parakeetUltra, languages: english) { _ in true }
    #expect(chosen?.model == .parakeetUltra)
    #expect(chosen?.languages == english)
  }

  @Test func aMissingSelectionFallsBackLikeDictation() {
    let chosen = MeetingModel.choose(selected: .parakeetUltra, languages: english) {
      $0 != .parakeetUltra
    }
    #expect(chosen?.model == .largeV3Turbo)
  }

  @Test func noDetectorMeansNoModel() {
    #expect(
      MeetingModel.choose(selected: .largeV3Turbo, languages: english) { $0 != .speechDetector }
        == nil)
  }

  @Test func nothingReadyMeansNoModel() {
    #expect(
      MeetingModel.choose(selected: .largeV3Turbo, languages: english) { $0 == .speechDetector }
        == nil)
  }

  @Test func timedTextNeverEndsBeforeItStarts() {
    #expect(TimedText(start: 2, end: 1, text: "x").end == 2)
  }
}
