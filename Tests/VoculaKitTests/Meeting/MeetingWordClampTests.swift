import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingWordClampTests {
  private let speech = [0.0...3.9, 4.9...9.3]

  private func clamp(_ start: Double, _ end: Double) -> TimedText? {
    MeetingPieces.clamped([TimedText(start: start, end: end, text: "w")], to: speech).first
  }

  @Test func aWordStretchedOverAPauseEndsWhereSpeechEnds() {
    #expect(clamp(3.44, 4.56) == TimedText(start: 3.44, end: 3.9, text: "w"))
  }

  @Test func aWordStartingInAPauseStartsWhereSpeechStarts() {
    #expect(clamp(4.6, 5.36) == TimedText(start: 4.9, end: 5.36, text: "w"))
  }

  @Test func aWordWhollyInAPauseBecomesAPointAtTheNearerEdge() {
    #expect(clamp(4.56, 4.88) == TimedText(start: 4.9, end: 4.9, text: "w"))
    #expect(clamp(3.95, 4.2) == TimedText(start: 3.9, end: 3.9, text: "w"))
  }

  @Test func aWordAfterTheLastSpeechBecomesAPointAtItsEnd() {
    #expect(clamp(9.5, 9.8) == TimedText(start: 9.3, end: 9.3, text: "w"))
  }

  @Test func aWordInsideSpeechIsLeftAlone() {
    #expect(clamp(1.0, 1.3) == TimedText(start: 1.0, end: 1.3, text: "w"))
  }

  @Test func withoutSpeechTheWordsAreLeftAlone() {
    let words = [TimedText(start: 1, end: 2, text: "w")]
    #expect(MeetingPieces.clamped(words, to: []) == words)
  }
}
