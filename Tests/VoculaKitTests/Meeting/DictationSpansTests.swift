import Testing

@testable import VoculaKit

@Suite struct DictationSpansTests {
  let s: UInt64 = 1_000_000_000

  @Test func aStopClosesItsSpan() {
    var spans = DictationSpans()
    #expect(spans.received(.start(session: 1), generation: 1, at: 10 * s).isEmpty)
    let closed = spans.received(.stop(session: 1, reason: .releasedHold), generation: 1, at: 12 * s)
    #expect(closed == [DictationSpan(start: 10 * s, end: 12 * s)])
  }

  @Test func aCancelClosesItsSpan() {
    var spans = DictationSpans()
    _ = spans.received(.start(session: 1), generation: 1, at: 0)
    let closed = spans.received(.cancel(session: 1, reason: .tooShort), generation: 1, at: s)
    #expect(closed == [DictationSpan(start: 0, end: s)])
  }

  @Test func anotherSessionsStopClosesNothing() {
    var spans = DictationSpans()
    _ = spans.received(.start(session: 1), generation: 1, at: 0)
    #expect(spans.received(.stop(session: 2, reason: .releasedHold), generation: 1, at: s).isEmpty)
    let closed = spans.received(.stop(session: 1, reason: .releasedHold), generation: 1, at: 2 * s)
    #expect(closed == [DictationSpan(start: 0, end: 2 * s)])
  }

  @Test func aStopFromAnotherGenerationClosesNothing() {
    var spans = DictationSpans()
    _ = spans.received(.start(session: 1), generation: 1, at: 0)
    #expect(
      spans.received(.stop(session: 1, reason: .releasedHold), generation: 2, at: 2 * s).isEmpty)
  }

  @Test func theNextStartClosesTheOpenSpan() {
    var spans = DictationSpans()
    _ = spans.received(.start(session: 1), generation: 1, at: 10 * s)
    let closed = spans.received(.start(session: 2), generation: 1, at: 15 * s)
    #expect(closed == [DictationSpan(start: 10 * s, end: 15 * s)])
    #expect(spans.meetingEnded(at: 16 * s) == [DictationSpan(start: 15 * s, end: 16 * s)])
  }

  @Test func aSpanIsCappedAtThreeMinutes() {
    var spans = DictationSpans()
    _ = spans.received(.start(session: 1), generation: 1, at: 0)
    let closed = spans.received(
      .stop(session: 1, reason: .releasedHold), generation: 1, at: 200 * s)
    #expect(closed == [DictationSpan(start: 0, end: 180 * s)])
  }

  @Test func aCloseBeforeTheOpenDoesNotTrap() {
    var spans = DictationSpans()
    _ = spans.received(.start(session: 1), generation: 1, at: 10 * s)
    let closed = spans.received(.stop(session: 1, reason: .releasedHold), generation: 1, at: 5 * s)
    #expect(closed == [DictationSpan(start: 10 * s, end: 10 * s)])
    _ = spans.received(.start(session: 2), generation: 1, at: .max - 1)
    #expect(spans.meetingEnded(at: .max).first?.end == .max)
  }

  @Test func aGenerationEndClosesOnlyItsOwnSpan() {
    var spans = DictationSpans()
    _ = spans.received(.start(session: 1), generation: 1, at: 0)
    #expect(spans.generationEnded(2, at: 3 * s).isEmpty)
    #expect(spans.generationEnded(1, at: 4 * s) == [DictationSpan(start: 0, end: 4 * s)])
  }

  @Test func theMeetingEndClosesWhatIsOpen() {
    var spans = DictationSpans()
    _ = spans.received(.start(session: 1), generation: 1, at: 0)
    #expect(spans.meetingEnded(at: 7 * s) == [DictationSpan(start: 0, end: 7 * s)])
    #expect(spans.meetingEnded(at: 8 * s).isEmpty)
  }

  @Test(
    "ACCEPTED COST: a dictation abandoned without a signal is marked until the next start or the cap"
  ) func abandoned() {
    var spans = DictationSpans()
    _ = spans.received(.start(session: 1), generation: 1, at: 0)
    #expect(spans.meetingEnded(at: 500 * s) == [DictationSpan(start: 0, end: 180 * s)])
  }
}
