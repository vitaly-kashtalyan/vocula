import Foundation
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

  @Test func anUtteranceNeverEndsBeforeItStarts() throws {
    #expect(MeetingUtterance(start: 3, end: 1, speaker: .me, text: "x").end == 3)
    let stored = Data(#"{"start":5,"end":4,"speaker":"me","text":"x"}"#.utf8)
    #expect(try JSONDecoder().decode(MeetingUtterance.self, from: stored).end == 5)
  }

  @Test func onlyARecognisedTranscriptNamesItsModel() {
    #expect(MeetingTranscript.empty.model == nil)
    #expect(MeetingTranscript.empty.utterances.isEmpty)
    #expect(
      MeetingTranscript.recognized(by: .parakeetUltra, utterances: []).model == "parakeetUltra")
  }

  @Test(arguments: [(true, 30, Duration.seconds(30)), (false, 30, nil)])
  func cleanUpAddsItsWaitOnlyWhenOn(enabled: Bool, seconds: Int, wait: Duration?) {
    #expect(DictationHold.refineWait(enabled: enabled, maximumSeconds: seconds) == wait)
  }
}
