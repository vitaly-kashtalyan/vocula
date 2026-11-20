import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingPiecesTests {
  private let window = 960_000

  private func segment(_ from: Int, _ to: Int) -> SpeechSegment {
    SpeechSegment(start: .milliseconds(from), end: .milliseconds(to), probability: 0.9)
  }

  @Test func segmentsUnderASecondApartArePacked() {
    let plan = MeetingPieces.plan(
      segments: [segment(0, 1_000), segment(1_500, 2_500)], count: window, isLast: true)
    #expect(plan.pieces == [0..<40_000])
    #expect(plan.carryFrom == nil)
  }

  @Test func aSecondApartSplits() {
    let plan = MeetingPieces.plan(
      segments: [segment(0, 1_000), segment(2_000, 3_000)], count: window, isLast: true)
    #expect(plan.pieces == [0..<16_000, 32_000..<48_000])
  }

  @Test func aLongSegmentIsCutAtThirtySeconds() {
    let plan = MeetingPieces.plan(
      segments: [segment(0, 70_000)], count: 1_120_000, isLast: true)
    #expect(plan.pieces == [0..<480_000, 480_000..<960_000, 960_000..<1_120_000])
  }

  @Test func speechAtTheEndIsCarried() {
    let plan = MeetingPieces.plan(
      segments: [segment(1_000, 2_000), segment(59_500, 59_900)], count: window, isLast: false)
    #expect(plan.pieces == [16_000..<32_000])
    #expect(plan.carryFrom == 952_000)
  }

  @Test func speechAcrossTheSeamIsCarriedOnce() {
    let first = MeetingPieces.plan(
      segments: [segment(59_000, 60_000)], count: window, isLast: false)
    #expect(first.pieces.isEmpty)
    #expect(first.carryFrom == 944_000)
    let carried = window - 944_000
    let second = MeetingPieces.plan(
      segments: [segment(0, 2_000)], count: carried + window, isLast: true)
    #expect(second.pieces == [0..<32_000])
  }

  @Test func aFullPieceIsNotCarried() {
    let plan = MeetingPieces.plan(segments: [segment(30_000, 60_000)], count: window, isLast: false)
    #expect(plan.pieces == [480_000..<960_000])
    #expect(plan.carryFrom == nil)
  }

  @Test func theLastWindowCarriesNothing() {
    let plan = MeetingPieces.plan(segments: [segment(59_500, 59_900)], count: window, isLast: true)
    #expect(plan.pieces == [952_000..<958_400])
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

  @Test func aQuietWindowIsLifted() {
    let quiet = (0..<16_000).map { Int16($0 % 2 == 0 ? 328 : -328) }
    let lifted = MeetingPieces.lift(quiet)
    #expect((lifted.map(abs).max() ?? 0) >= 0.29)
  }

  @Test func zerosAreNotLifted() {
    #expect(MeetingPieces.lift([Int16](repeating: 0, count: 1_000)).allSatisfy { $0 == 0 })
  }
}
