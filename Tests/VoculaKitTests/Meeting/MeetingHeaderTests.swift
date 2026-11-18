import Foundation
import Testing

@testable import VoculaKit

struct MeetingHeaderTests {
  @Test func aNewHeaderIsRecording() {
    let h = MeetingHeader(id: UUID(), startedAt: Date(timeIntervalSince1970: 1), anchor: 2)
    #expect(h.state == .recording)
    #expect(h.end == nil)
    #expect(h.endedBy == nil)
    #expect(h.dictations.isEmpty)
  }

  @Test func hostTimeMapsOntoTheStartDate() {
    let h = MeetingHeader(
      id: UUID(), startedAt: Date(timeIntervalSince1970: 1_000), anchor: 5_000_000_000)
    #expect(h.date(atHost: 7_500_000_000) == Date(timeIntervalSince1970: 1_002.5))
  }

  @Test func anEarlierHostTimeMapsToTheStart() {
    let h = MeetingHeader(
      id: UUID(), startedAt: Date(timeIntervalSince1970: 1_000), anchor: 5_000_000_000)
    #expect(h.date(atHost: 4_999_999_999) == h.startedAt)
  }

  @Test func hostTimeArithmeticSaturates() {
    #expect(HostTime.elapsed(from: 5, to: 3) == 0)
    #expect(HostTime.elapsed(from: 3, to: 5) == 2)
    #expect(HostTime.adding(.max, 1) == .max)
    #expect(HostTime.nanos(.nan) == 0)
    #expect(HostTime.nanos(-1) == 0)
    #expect(HostTime.nanos(1e30) == .max)
    #expect(HostTime.nanos(1.5) == 1_500_000_000)
  }

  @Test func theHeaderSurvivesJSON() throws {
    var h = MeetingHeader(id: UUID(), startedAt: Date(timeIntervalSince1970: 1_000), anchor: 9)
    h.finish(atHost: 1_000_000_000_009, by: .sleep)
    h.dictations = [DictationSpan(start: 1, end: 2), DictationSpan(start: 3, end: 4)]
    let back = try JSONDecoder().decode(MeetingHeader.self, from: JSONEncoder().encode(h))
    #expect(back == h)
  }

  @Test func finishingSetsTheEndTheStateAndTheReasonTogether() {
    var h = MeetingHeader(
      id: UUID(), startedAt: Date(timeIntervalSince1970: 1_000), anchor: 5_000_000_000)
    h.finish(atHost: 7_500_000_000, by: .sleep)
    #expect(h.end == Date(timeIntervalSince1970: 1_002.5))
    #expect(h.state == .recorded)
    #expect(h.endedBy == .sleep)
  }

  @Test func aSpanNeverEndsBeforeItStarts() {
    #expect(DictationSpan(start: 5, end: 3) == DictationSpan(start: 5, end: 5))
    #expect(DictationSpan(start: 5, end: 3).end == 5)
  }

  @Test func aDecodedSpanIsOrderedAndNeverThrows() throws {
    let decoder = JSONDecoder()
    let backwards = try decoder.decode(DictationSpan.self, from: Data(#"{"start":5,"end":3}"#.utf8))
    #expect(backwards.end == 5)
    let partial = try? decoder.decode(DictationSpan.self, from: Data(#"{"start":5}"#.utf8))
    #expect(partial == DictationSpan(start: 5, end: 5))
  }

  @Test func theAggregateIsInvisibleToDictation() {
    #expect(SyntheticInputDevice.isKnownSynthetic(uid: MeetingAggregate.uid(UUID()), name: "x"))
    #expect(SyntheticInputDevice.isKnownSynthetic(uid: "x", name: MeetingAggregate.name))
  }

  @Test func theSoundFloorsArePinned() {
    #expect(MeetingTrack.mic.soundFloor == 328)
    #expect(MeetingTrack.system.soundFloor == 1)
  }
}
