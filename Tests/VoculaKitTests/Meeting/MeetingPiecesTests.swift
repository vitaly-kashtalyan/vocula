import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingPiecesTests {
  private let window = 960_000

  private func segment(_ from: Int, _ to: Int) -> SpeechSegment {
    SpeechSegment(start: .milliseconds(from), end: .milliseconds(to), probability: 0.9)
  }

  @Test func aPauseUnderThreeSecondsStaysInOnePiece() {
    let plan = MeetingPieces.plan(
      segments: [segment(1_000, 2_000), segment(4_500, 5_500)], count: window, isLast: true)
    #expect(plan.pieces == [8_000..<96_000])
    #expect(plan.carryFrom == nil)
  }

  @Test func threeSecondsApartSplits() {
    let plan = MeetingPieces.plan(
      segments: [segment(1_000, 2_000), segment(5_000, 6_000)], count: window, isLast: true)
    #expect(plan.pieces == [8_000..<40_000, 72_000..<104_000])
  }

  @Test func aPieceTakesHalfASecondEitherSide() {
    let plan = MeetingPieces.plan(segments: [segment(10_000, 12_000)], count: window, isLast: true)
    #expect(plan.pieces == [152_000..<200_000])
  }

  @Test func aPieceStopsAtTheEdgesOfItsBuffer() {
    let plan = MeetingPieces.plan(segments: [segment(200, 59_900)], count: window, isLast: true)
    #expect(plan.pieces == [0..<483_200, 483_200..<960_000])
  }

  @Test func aLongSegmentIsCutAtThirtySecondsWithoutOverlap() {
    let plan = MeetingPieces.plan(
      segments: [segment(0, 70_000)], count: 1_120_000, isLast: true)
    #expect(plan.pieces == [0..<480_000, 480_000..<960_000, 960_000..<1_120_000])
  }

  @Test func speechAtTheEndIsCarriedWithHalfASecondBeforeIt() {
    let plan = MeetingPieces.plan(
      segments: [segment(1_000, 2_000), segment(59_500, 59_900)], count: window, isLast: false)
    #expect(plan.pieces == [8_000..<40_000])
    #expect(plan.carryFrom == 944_000)
  }

  @Test func speechWithinThreeSecondsOfTheEndIsCarried() {
    let plan = MeetingPieces.plan(
      segments: [segment(1_000, 2_000), segment(57_500, 58_000)], count: window, isLast: false)
    #expect(plan.pieces == [8_000..<40_000])
    #expect(plan.carryFrom == 912_000)
  }

  @Test func theCarryNeverReachesBackPastHalfwayToTheLastPiece() {
    let plan = MeetingPieces.plan(
      segments: [segment(29_000, 59_000), segment(59_300, 59_800)], count: window, isLast: false)
    #expect(plan.pieces == [456_000..<946_400])
    #expect(plan.carryFrom == 946_400)
  }

  @Test func speechAcrossTheSeamIsCarriedOnce() {
    let first = MeetingPieces.plan(
      segments: [segment(59_000, 60_000)], count: window, isLast: false)
    #expect(first.pieces.isEmpty)
    #expect(first.carryFrom == 936_000)
    let carried = window - 936_000
    let second = MeetingPieces.plan(
      segments: [segment(500, 2_500)], count: carried + window, isLast: true)
    #expect(second.pieces == [0..<48_000])
  }

  @Test func aFullPieceIsNotCarried() {
    let plan = MeetingPieces.plan(segments: [segment(30_000, 60_000)], count: window, isLast: false)
    #expect(plan.pieces == [472_000..<960_000])
    #expect(plan.carryFrom == nil)
  }

  @Test func theLastWindowCarriesNothing() {
    let plan = MeetingPieces.plan(segments: [segment(59_500, 59_900)], count: window, isLast: true)
    #expect(plan.pieces == [944_000..<960_000])
    #expect(plan.carryFrom == nil)
  }

  @Test func shortPiecesArePadded() {
    let short = [Float](repeating: 0.5, count: 3_200)
    let padded = MeetingPieces.padded(short)
    #expect(padded.count == 8_000)
    #expect(Array(padded.prefix(3_200)) == short)
    #expect(padded.suffix(4_800).allSatisfy { $0 == 0 })
    #expect(MeetingPieces.padded([Float](repeating: 0.1, count: 9_000)).count == 9_000)
  }

  @Test func aQuietWindowIsLiftedAfterALoudCarry() {
    let carry = [Float](repeating: 0.9, count: 100)
    let quiet = (0..<16_000).map { Int16($0 % 2 == 0 ? 328 : -328) }
    let buffer = MeetingPieces.buffer(carry: carry, window: quiet)
    #expect(buffer.count == 16_100)
    #expect(Array(buffer.prefix(100)) == carry)
    #expect((buffer.dropFirst(100).map(abs).max() ?? 0) >= 0.29)
  }

  @Test func zerosAreNotLifted() {
    #expect(
      MeetingPieces.buffer(carry: [], window: [Int16](repeating: 0, count: 1_000))
        .allSatisfy { $0 == 0 })
  }
}
