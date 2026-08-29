import Testing

@testable import VoculaKit

private func ms(_ value: Int) -> Timestamp { .milliseconds(value) }

private let comboBinding = KeyBinding(
  klass: .comboWithKey, keyCode: 0x02,
  modifiers: [.leftControl, .leftOption])
private let functionBinding = KeyBinding(klass: .functionKey, keyCode: 0x69, modifiers: [])
private let pairBinding = KeyBinding(
  klass: .modifierPair, keyCode: nil,
  modifiers: [.leftControl, .leftOption])

private func machine(_ primary: KeyBinding) -> GestureStateMachine {
  GestureStateMachine(config: GestureConfig(primary: primary))
}

@Suite("Gesture — edges and all four classes")
struct GestureEdgeTests {
  @Test(
    "a foreign key inside the collision window cancels retroactively",
    arguments: [KeyBinding.fn, pairBinding])
  func collisionCancelsForModifierClasses(binding: KeyBinding) {
    var sm = machine(binding)
    _ = sm.handle(.bindingDown(ms(0)))
    let out = sm.handle(.foreignKey(ms(100)))
    #expect(out.signals == [.cancel(session: 1, reason: .collision)])
    #expect(sm.isRecording == false)
  }

  @Test(
    "the collision rule does not apply to combos or function keys",
    arguments: [comboBinding, functionBinding])
  func collisionIgnoredForUnambiguousClasses(binding: KeyBinding) {
    var sm = machine(binding)
    _ = sm.handle(.bindingDown(ms(0)))
    #expect(sm.handle(.foreignKey(ms(100))).signals.isEmpty)
    #expect(sm.isRecording == true)
  }

  @Test(
    "a foreign key cancels a held bare modifier however late it arrives",
    arguments: [KeyBinding.fn, pairBinding])
  func collisionDoesNotExpireWhileTheModifierIsHeld(binding: KeyBinding) {
    var sm = machine(binding)
    _ = sm.handle(.bindingDown(ms(0)))
    _ = sm.handle(.tick(ms(250)))
    let out = sm.handle(.foreignKey(ms(3_000)))
    #expect(out.signals == [.cancel(session: 1, reason: .collision)])
    #expect(sm.isRecording == false)
  }

  @Test(
    "a foreign key never cancels a combo or function-key binding",
    arguments: [comboBinding, functionBinding])
  func collisionIgnoredLateForUnambiguousClasses(binding: KeyBinding) {
    var sm = machine(binding)
    _ = sm.handle(.bindingDown(ms(0)))
    _ = sm.handle(.tick(ms(250)))
    #expect(sm.handle(.foreignKey(ms(900))).signals.isEmpty)
    #expect(sm.isRecording == true)
  }

  @Test(
    "Esc cancels for the whole length of the session, in every class",
    arguments: [KeyBinding.fn, pairBinding, comboBinding, functionBinding])
  func escapeCancelsEverywhere(binding: KeyBinding) {
    var sm = machine(binding)
    _ = sm.handle(.bindingDown(ms(0)))
    _ = sm.handle(.tick(ms(250)))
    let out = sm.handle(.escape(ms(120_000)))
    #expect(out.signals == [.cancel(session: 1, reason: .escape)])
  }

  @Test("Esc outside a session does nothing — the app only takes it while recording")
  func escapeOutsideSessionIsInert() {
    var sm = machine(.fn)
    #expect(sm.handle(.escape(ms(10))).signals.isEmpty)
    #expect(sm.isRecording == false)
  }

  @Test("isRecording drives Esc absorption: false at rest, true while live")
  func isRecordingTracksLiveRecording() {
    var sm = machine(.fn)
    #expect(sm.isRecording == false)
    _ = sm.handle(.bindingDown(ms(0)))
    #expect(sm.isRecording == true)
    _ = sm.handle(.tick(ms(250)))
    _ = sm.handle(.bindingUp(ms(500)))
    #expect(sm.isRecording == false)
  }

  @Test(
    "recording starts on the first touch in every class",
    arguments: [KeyBinding.fn, pairBinding, comboBinding, functionBinding])
  func startsOnFirstTouchInEveryClass(binding: KeyBinding) {
    var sm = machine(binding)
    #expect(sm.handle(.bindingDown(ms(0))).signals == [.start(session: 1)])
  }

  @Test("debounce: a single press with jitter does not become a double tap")
  func debounce() {
    var sm = machine(.fn)
    _ = sm.handle(.bindingDown(ms(0)))
    #expect(sm.handle(.bindingDown(ms(3))).signals.isEmpty)
    #expect(sm.handle(.bindingDown(ms(7))).signals.isEmpty)
    _ = sm.handle(.tick(ms(250)))
    #expect(
      sm.handle(.bindingUp(ms(600))).signals
        == [.stop(session: 1, reason: .releasedHold)])
  }

  @Test(
    "abandon silently drops a recording in progress, and the next press starts fresh",
    arguments: [KeyBinding.fn, pairBinding, comboBinding, functionBinding])
  func abandonDropsRecordingSilently(binding: KeyBinding) {
    var sm = machine(binding)
    _ = sm.handle(.bindingDown(ms(0)))
    #expect(sm.isRecording == true)
    sm.abandon()
    #expect(sm.isRecording == false)
    #expect(sm.isHoldingBinding == false)
    #expect(sm.handle(.bindingDown(ms(1_000))).signals == [.start(session: 2)])
  }

  @Test("session numbers increase monotonically and never repeat")
  func sessionNumbersIncrease() {
    var sm = machine(.fn)
    for expected in 1...3 {
      #expect(
        sm.handle(.bindingDown(ms(expected * 10_000))).signals
          == [.start(session: expected)])
      _ = sm.handle(.tick(ms(expected * 10_000 + 250)))
      _ = sm.handle(.bindingUp(ms(expected * 10_000 + 900)))
    }
  }
}
