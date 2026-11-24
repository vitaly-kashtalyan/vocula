import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingSpeakerAssignmentTests {
  private let two = [
    SpeakerTurn(speaker: "A", start: 0, end: 10), SpeakerTurn(speaker: "B", start: 10, end: 20),
  ]

  private func words(_ spans: [(Double, Double)]) -> [TimedText] {
    spans.map { TimedText(start: $0.0, end: $0.1, text: "w.") }
  }

  private func assign(_ spans: [(Double, Double)], _ turns: [SpeakerTurn]) -> [MeetingSpeaker] {
    MeetingSpeakerAssignment.assign(words(spans), turns: turns)
  }

  private func said(_ items: [(String, Double, Double)], _ turns: [SpeakerTurn])
    -> [MeetingSpeaker]
  {
    MeetingSpeakerAssignment.assign(
      items.map { TimedText(start: $0.1, end: $0.2, text: $0.0) }, turns: turns)
  }

  @Test func theConstantsAreTheSpecsStartingValues() {
    #expect(MeetingSpeakerAssignment.pointSpan == 0.05)
    #expect(MeetingSpeakerAssignment.minCoverage == 0.5)
    #expect(MeetingSpeakerAssignment.overlapCoverage == 0.3)
    #expect(MeetingSpeakerAssignment.nearestReach == 2.0)
    #expect(MeetingSpeakerAssignment.sentencePause == 2.0)
    #expect(MeetingSpeakerAssignment.longestSentence == 50)
  }

  @Test func aWordInsideOneTurnTakesItsSpeaker() {
    #expect(assign([(2.0, 2.5)], two) == [.numbered(1)])
  }

  @Test func speakersAreNumberedByFirstWordInStartOrder() {
    #expect(assign([(12.0, 12.5), (3.0, 3.5)], two) == [.numbered(2), .numbered(1)])
  }

  @Test func aShortWordAcrossABoundaryUsesItsMidpoint() {
    #expect(assign([(9.98, 10.01)], two) == [.numbered(1)])
  }

  @Test func aZeroLengthWordIsAPoint() {
    #expect(assign([(3.0, 3.0)], two) == [.numbered(1)])
  }

  @Test func aPointOnABoundaryBelongsToTheLaterTurn() {
    #expect(assign([(2.0, 2.5), (10.0, 10.0)], two) == [.numbered(1), .numbered(2)])
  }

  @Test func aWordMostlyOutsideTheOnlyTurnTakesItsSpeaker() {
    let turns = [SpeakerTurn(speaker: "A", start: 0, end: 2)]
    #expect(assign([(1.75, 2.5)], turns) == [.numbered(1)])
  }

  @Test func exactlyHalfCoveredTakesTheSpeaker() {
    let turns = [SpeakerTurn(speaker: "A", start: 0, end: 2)]
    #expect(assign([(1.5, 2.5)], turns) == [.numbered(1)])
  }

  @Test func exactlyOverlapCoverageIsOverlap() {
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 0.3), SpeakerTurn(speaker: "B", start: 0.3, end: 1),
    ]
    #expect(assign([(0, 1)], turns) == [.others])
  }

  @Test func aReversedTurnIsEmpty() {
    #expect(SpeakerTurn(speaker: "A", start: 5, end: 2).end == 5)
  }

  @Test func aSpeakersTurnsAddUp() {
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 1), SpeakerTurn(speaker: "A", start: 1, end: 2),
    ]
    #expect(assign([(0.5, 1.5)], turns) == [.numbered(1)])
  }

  @Test func overlapStaysOthers() {
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 10), SpeakerTurn(speaker: "B", start: 9, end: 20),
    ]
    #expect(
      assign([(2.0, 2.5), (9.25, 9.75), (9.5, 10.5), (9.75, 10.75)], turns)
        == [.numbered(1), .others, .others, .numbered(2)])
  }

  @Test func wordsOutsideEveryTurnStayOthers() {
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 5), SpeakerTurn(speaker: "B", start: 6, end: 10),
    ]
    #expect(
      assign([(-3.0, -2.5), (25.0, 25.5), (5.25, 5.75)], turns) == [.others, .others, .others])
  }

  @Test func noTurnsMeansAllOthers() {
    #expect(assign([(1, 2), (3, 4)], []) == [.others, .others])
  }

  @Test func turnsPastTheLastWordAreHarmless() {
    let turns = two + [SpeakerTurn(speaker: "C", start: 100, end: 200)]
    #expect(assign([(2.0, 2.5)], turns) == [.numbered(1)])
  }

  @Test func aSpeakerWithoutAttributedWordsTakesNoNumber() {
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 5), SpeakerTurn(speaker: "B", start: 5, end: 10),
      SpeakerTurn(speaker: "C", start: 10, end: 15),
    ]
    #expect(assign([(1.0, 1.5), (11.0, 11.5)], turns) == [.numbered(1), .numbered(2)])
  }

  @Test func aWordInAPauseInsideOneSpeakersSpeechTakesTheirNumber() {
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 2), SpeakerTurn(speaker: "A", start: 3, end: 5),
    ]
    #expect(
      assign([(1.0, 1.5), (2.25, 2.75), (3.5, 4.0)], turns)
        == [.numbered(1), .numbered(1), .numbered(1)])
  }

  @Test func aWordInAPauseEquallyFarFromTwoSpeakersStaysOthers() {
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 2), SpeakerTurn(speaker: "B", start: 3, end: 5),
    ]
    #expect(
      assign([(1.0, 1.5), (2.25, 2.75), (3.5, 4.0)], turns)
        == [.numbered(1), .others, .numbered(2)])
  }

  @Test func anOverlappedWordInsideOneSpeakersSpeechStaysOthers() {
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 10), SpeakerTurn(speaker: "B", start: 4, end: 6),
    ]
    #expect(
      assign([(1.0, 1.5), (4.5, 5.0), (8.0, 8.5)], turns)
        == [.numbered(1), .others, .numbered(1)])
  }

  @Test func aPauseWordIsJudgedByItsNeighboursInTime() {
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 2), SpeakerTurn(speaker: "A", start: 3, end: 5),
    ]
    #expect(
      assign([(3.5, 4.0), (2.25, 2.75), (1.0, 1.5)], turns)
        == [.numbered(1), .numbered(1), .numbered(1)])
  }

  @Test func aPauseWordAtEitherEndTakesTheSpeakerWithinReach() {
    let turns = [SpeakerTurn(speaker: "A", start: 1, end: 2)]
    #expect(
      assign([(0.0, 0.5), (1.25, 1.75), (2.5, 3.0), (4.5, 5.0)], turns)
        == [.numbered(1), .numbered(1), .numbered(1), .others])
  }

  @Test func aPauseWordBetweenTwoSpeakersTakesTheNearer() {
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 2), SpeakerTurn(speaker: "B", start: 3, end: 5),
    ]
    #expect(
      assign([(1.0, 1.5), (2.1, 2.4), (3.5, 4.0)], turns)
        == [.numbered(1), .numbered(1), .numbered(2)])
  }

  @Test func aWordFlippedInsideASentenceTakesTheSentencesSpeaker() {
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 2), SpeakerTurn(speaker: "B", start: 2, end: 2.4),
      SpeakerTurn(speaker: "A", start: 2.4, end: 5),
    ]
    let spoken = [
      ("we", 0.5, 0.8), ("will", 1.0, 1.3), ("ship", 2.05, 2.35), ("it", 2.5, 2.8),
      ("tomorrow.", 3.0, 3.5),
    ]
    #expect(said(spoken, turns) == Array(repeating: .numbered(1), count: 5))
  }

  @Test func aSentenceOfItsOwnKeepsItsSpeaker() {
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 2), SpeakerTurn(speaker: "B", start: 2, end: 3),
      SpeakerTurn(speaker: "A", start: 3, end: 5),
    ]
    let spoken = [
      ("we", 0.5, 0.8), ("ship.", 1.0, 1.3), ("agreed.", 2.2, 2.6), ("then", 3.2, 3.5),
      ("tomorrow.", 3.7, 4.2),
    ]
    #expect(
      said(spoken, turns) == [.numbered(1), .numbered(1), .numbered(2), .numbered(1), .numbered(1)])
  }

  @Test func aSentenceSplitEvenlyIsLeftAlone() {
    let spoken = [("one", 0.5, 0.8), ("two", 1.0, 1.3), ("three", 2.2, 2.5), ("four", 2.7, 3.0)]
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 2), SpeakerTurn(speaker: "B", start: 2, end: 4),
    ]
    #expect(said(spoken, turns) == [.numbered(1), .numbered(1), .numbered(2), .numbered(2)])
  }

  @Test func aLongPauseEndsASentence() {
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 2), SpeakerTurn(speaker: "B", start: 4, end: 6),
    ]
    let spoken = [("we", 0.3, 0.6), ("ship", 0.8, 1.1), ("it", 1.3, 1.6), ("fine", 4.2, 4.5)]
    #expect(said(spoken, turns) == [.numbered(1), .numbered(1), .numbered(1), .numbered(2)])
  }

  @Test func aSentenceLongerThanTheLimitIsLeftAlone() {
    let turns = [
      SpeakerTurn(speaker: "A", start: 0, end: 25), SpeakerTurn(speaker: "B", start: 25, end: 25.4),
      SpeakerTurn(speaker: "A", start: 25.4, end: 100),
    ]
    let spoken = (0...MeetingSpeakerAssignment.longestSentence).map { i in
      ("w", Double(i) * 0.5, Double(i) * 0.5 + 0.3)
    }
    #expect(said(spoken, turns).last == .numbered(2))
  }

}
