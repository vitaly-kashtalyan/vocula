import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingSpeakerAssignmentTests {
  private let two = [
    SpeakerTurn(speaker: "A", start: 0, end: 10), SpeakerTurn(speaker: "B", start: 10, end: 20),
  ]

  private func words(_ spans: [(Double, Double)]) -> [TimedText] {
    spans.map { TimedText(start: $0.0, end: $0.1, text: "w") }
  }

  private func assign(_ spans: [(Double, Double)], _ turns: [SpeakerTurn]) -> [MeetingSpeaker] {
    MeetingSpeakerAssignment.assign(words(spans), turns: turns)
  }

  @Test func theConstantsAreTheSpecsStartingValues() {
    #expect(MeetingSpeakerAssignment.pointSpan == 0.05)
    #expect(MeetingSpeakerAssignment.minCoverage == 0.5)
    #expect(MeetingSpeakerAssignment.overlapCoverage == 0.3)
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

  @Test func aWordMostlyOutsideTurnsStaysOthers() {
    let turns = [SpeakerTurn(speaker: "A", start: 0, end: 2)]
    #expect(assign([(1.75, 2.5)], turns) == [.others])
  }

  @Test func exactlyHalfCoveredTakesTheSpeaker() {
    let turns = [SpeakerTurn(speaker: "A", start: 0, end: 2)]
    #expect(assign([(1.5, 2.5)], turns) == [.numbered(1)])
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
      assign([(-1.0, -0.5), (25.0, 25.5), (5.25, 5.75)], turns) == [.others, .others, .others])
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
}
