import Testing

@testable import VoculaKit

private func ms(_ value: Int) -> Timestamp { .milliseconds(value) }

private func machine(primary: KeyBinding = .fn) -> GestureStateMachine {
  GestureStateMachine(config: GestureConfig(primary: primary, timings: .default))
}

@Suite("Gesture — core")
struct GestureCoreTests {
  @Test("recording starts on the press, and runs until the duration limit")
  func startsOnPress() {
    var sm = machine()
    let out = sm.handle(.bindingDown(ms(0)))
    #expect(out.signals == [.start(session: 1)])
    #expect(out.nextDeadline == ms(180_000))
  }

  @Test("a hold longer than the minimum is a recording")
  func holdIsRecognised() {
    var sm = machine()
    _ = sm.handle(.bindingDown(ms(0)))
    let out = sm.handle(.bindingUp(ms(450)))
    #expect(out.signals == [.stop(session: 1, reason: .releasedHold)])
    #expect(out.nextDeadline == nil)
  }

  @Test("a 200 ms touch is discarded by the minimum")
  func shortHoldIsDiscarded() {
    var sm = machine()
    _ = sm.handle(.bindingDown(ms(0)))
    let out = sm.handle(.bindingUp(ms(200)))
    #expect(out.signals == [.cancel(session: 1, reason: .tooShort)])
  }

  @Test("a release at exactly minRecording produces a recording, not a discard")
  func releaseAtMinRecordingBoundaryIsARecording() {
    var sm = machine()
    _ = sm.handle(.bindingDown(ms(0)))
    let out = sm.handle(.bindingUp(ms(300)))
    #expect(out.signals == [.stop(session: 1, reason: .releasedHold)])
  }

  @Test("key auto-repeat does not fabricate a second touch")
  func autorepeatIgnored() {
    var sm = machine()
    _ = sm.handle(.bindingDown(ms(0)))
    #expect(sm.handle(.bindingDown(ms(40))).signals.isEmpty)
    #expect(sm.handle(.bindingDown(ms(300))).signals.isEmpty)
  }

  @Test("two touches in quick succession are two separate recordings")
  func quickSecondTouchIsItsOwnSession() {
    var sm = machine()
    _ = sm.handle(.bindingDown(ms(0)))
    #expect(
      sm.handle(.bindingUp(ms(400))).signals
        == [.stop(session: 1, reason: .releasedHold)])
    #expect(sm.handle(.bindingDown(ms(460))).signals == [.start(session: 2)])
  }

  @Test("the duration limit closes a hold and the later release is ignored")
  func limitClosesTheHold() {
    var sm = machine()
    _ = sm.handle(.bindingDown(ms(0)))
    let limit = sm.handle(.tick(ms(180_000)))
    #expect(limit.signals == [.stop(session: 1, reason: .durationLimit)])
    #expect(sm.handle(.bindingUp(ms(190_000))).signals.isEmpty)
  }

  @Test("after the limit the next press starts a NEW session")
  func pressAfterTheLimitStartsANewSession() {
    var sm = machine()
    _ = sm.handle(.bindingDown(ms(0)))
    _ = sm.handle(.tick(ms(180_000)))
    #expect(sm.handle(.bindingDown(ms(190_000))).signals == [.start(session: 2)])
  }

  @Test("an early tick does not close a recording that is still inside the limit")
  func earlyTickIsIgnored() {
    var sm = machine()
    _ = sm.handle(.bindingDown(ms(0)))
    let early = sm.handle(.tick(ms(1_000)))
    #expect(early.signals.isEmpty)
    #expect(early.nextDeadline == ms(180_000))
  }

  @Test("a tick on an idle machine emits no signal")
  func idleTickEmitsNoSignal() {
    var sm = machine()
    #expect(sm.handle(.tick(ms(1_000))).signals.isEmpty)
  }
}
