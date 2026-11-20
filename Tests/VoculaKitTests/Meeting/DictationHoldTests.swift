import Foundation
import Testing

@testable import VoculaKit

@Suite struct DictationHoldTests {
  let s: UInt64 = 1_000_000_000

  private func hold(refine: Duration? = nil) -> DictationHold {
    DictationHold(passDeadline: { max(.seconds(30), $0) }, refineWait: { refine })
  }

  @Test func aHeldKeyHolds() {
    var hold = hold()
    hold.received(.start(session: 1), at: 0)
    #expect(hold.clearsAt(10 * s) != nil)
  }

  @Test func aStopHoldsForItsDeadlineAndRefine() {
    var hold = hold(refine: .seconds(30))
    hold.received(.start(session: 1), at: 0)
    hold.received(.stop(session: 1, reason: .releasedHold), at: 40 * s)
    #expect(hold.clearsAt(109 * s) != nil)
    #expect(hold.clearsAt(110 * s) == nil)
  }

  @Test func refineOffAddsNothing() {
    var hold = hold()
    hold.received(.start(session: 1), at: 0)
    hold.received(.stop(session: 1, reason: .releasedHold), at: 40 * s)
    #expect(hold.clearsAt(79 * s) != nil)
    #expect(hold.clearsAt(80 * s) == nil)
  }

  @Test func holdsChainLikeDictationsQueue() {
    var hold = hold()
    hold.received(.start(session: 1), at: 0)
    hold.received(.stop(session: 1, reason: .releasedHold), at: 10 * s)
    hold.received(.start(session: 2), at: 20 * s)
    hold.received(.stop(session: 2, reason: .releasedHold), at: 25 * s)
    #expect(hold.clearsAt(69 * s) != nil)
    #expect(hold.clearsAt(70 * s) == nil)
  }

  @Test func aStopWithoutAStartHolds() {
    var hold = hold()
    hold.received(.cancel(session: 7, reason: .tooShort), at: 100 * s)
    #expect(hold.clearsAt(129 * s) != nil)
    #expect(hold.clearsAt(130 * s) == nil)
  }

  @Test func aStartWithNoEndEndsAtTheCap() {
    var hold = hold()
    hold.received(.start(session: 1), at: 0)
    #expect(hold.clearsAt(179 * s) != nil)
    #expect(hold.clearsAt(359 * s) != nil)
    #expect(hold.clearsAt(360 * s) == nil)
  }

  @Test func theStreamEndingClosesAnOpenDictation() {
    var hold = hold()
    hold.received(.start(session: 1), at: 0)
    hold.streamEnded(at: 5 * s)
    #expect(hold.clearsAt(34 * s) != nil)
    #expect(hold.clearsAt(35 * s) == nil)
  }

  @Test func nothingHeldIsClear() {
    #expect(hold().clearsAt(0) == nil)
  }

  @Test func theGateWaitsAndReportsTheWait() async {
    let clock = TestClock(start: 0)
    let gate = MeetingHoldGate(
      hold: hold(), now: { clock.now() }, sleep: { try await clock.sleep(for: $0) })
    await gate.received(.start(session: 1))
    let waiting = Task { await gate.waitUntilClear() }
    await clock.untilSleeping()
    clock.advance(by: .seconds(1))
    await gate.received(.stop(session: 1, reason: .releasedHold))
    for _ in 0..<40 {
      await clock.untilSleeping()
      clock.advance(by: .seconds(1))
      if clock.now() >= 31 * s { break }
    }
    let waited = await waiting.value
    #expect(waited >= .seconds(31))
    #expect(await gate.waitUntilClear() == .zero)
  }
}
