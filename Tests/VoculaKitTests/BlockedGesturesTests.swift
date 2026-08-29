import Testing

@testable import VoculaKit

@Suite("Blocked gestures")
struct BlockedGesturesTests {
  @Test("an allowed gesture passes through untouched, and is asked once")
  func allowedGesturePassesThrough() {
    var gate = BlockedGestures()
    var asked = 0
    let allow = {
      asked += 1
      return true
    }
    #expect(gate.admits(.start(session: 1), isAllowed: allow) == .admit)
    #expect(
      gate.admits(
        .stop(session: 1, reason: .releasedHold),
        isAllowed: allow) == .admit)
    #expect(asked == 1)
  }

  @Test("a refused gesture is swallowed to its end, release included")
  func refusedGestureIsSwallowedWhole() {
    var gate = BlockedGestures()
    #expect(
      gate.admits(.start(session: 1), isAllowed: { false })
        == .refuse(session: 1))
    #expect(
      gate.admits(
        .stop(session: 1, reason: .releasedHold),
        isAllowed: {
          Issue.record("asked on stop")
          return true
        })
        == .swallow)
  }

  @Test("a refused gesture that reaches its duration limit stays swallowed")
  func refusedGestureAtTheLimitStaysSwallowed() {
    var gate = BlockedGestures()
    _ = gate.admits(.start(session: 1), isAllowed: { false })
    #expect(
      gate.admits(
        .stop(session: 1, reason: .durationLimit),
        isAllowed: { true }) == .swallow)
  }

  @Test("a signal for another session is admitted while a refusal is live")
  func anotherSessionIsNotSwallowedWithIt() {
    var gate = BlockedGestures()
    _ = gate.admits(.start(session: 1), isAllowed: { false })
    #expect(
      gate.admits(
        .stop(session: 2, reason: .releasedHold),
        isAllowed: { true }) == .admit)
  }

  @Test("the block does not survive into a later allowed gesture")
  func blockEndsWithItsOwnGesture() {
    var gate = BlockedGestures()
    _ = gate.admits(.start(session: 1), isAllowed: { false })
    _ = gate.admits(.cancel(session: 1, reason: .tooShort), isAllowed: { true })
    #expect(gate.admits(.start(session: 2), isAllowed: { true }) == .admit)
    #expect(
      gate.admits(
        .stop(session: 2, reason: .releasedHold),
        isAllowed: { true }) == .admit)
  }

  @Test("an abandoned refusal is cleared by the next allowed start")
  func abandonedRefusalDoesNotStrandTheGate() {
    var gate = BlockedGestures()
    _ = gate.admits(.start(session: 1), isAllowed: { false })
    #expect(gate.admits(.start(session: 2), isAllowed: { true }) == .admit)
    #expect(
      gate.admits(
        .stop(session: 1, reason: .releasedHold),
        isAllowed: { true }) == .admit)
  }
}
