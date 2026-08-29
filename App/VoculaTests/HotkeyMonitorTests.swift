import Foundation
import Testing

@testable import Vocula
@testable import VoculaKit

@MainActor
struct HotkeyMonitorTests {
  private enum Bit {
    static let control: UInt64 = 1 << 18
    static let alternate: UInt64 = 1 << 19
    static let fn: UInt64 = 1 << 23
    static let shift: UInt64 = 1 << 17
    static let command: UInt64 = 1 << 20
    static let leftControl: UInt64 = 0x0000_0001
    static let leftOption: UInt64 = 0x0000_0020
    static let leftShift: UInt64 = 0x0000_0002
  }
  private enum Code {
    static let fn: UInt16 = 0x3F
    static let command: UInt16 = 0x37
    static let l: UInt16 = 0x25
    static let a: UInt16 = 0x00
    static let escape: UInt16 = 0x35
    static let control: UInt16 = 0x3B
    static let option: UInt16 = 0x3A
    static let shift: UInt16 = 0x38
    static let d: UInt16 = 0x02
    static let f13: UInt16 = 0x69
  }

  private func flags(_ bits: UInt64...) -> UInt64 { bits.reduce(0, |) }

  private func down(_ keyCode: UInt16, _ f: UInt64 = 0, repeated: Bool = false) -> TapEvent {
    TapEvent(kind: .keyDown, keyCode: keyCode, flags: f, isRepeat: repeated, userData: 0)
  }
  private func up(_ keyCode: UInt16, _ f: UInt64 = 0) -> TapEvent {
    TapEvent(kind: .keyUp, keyCode: keyCode, flags: f, isRepeat: false, userData: 0)
  }
  private func modifier(_ keyCode: UInt16, _ f: UInt64) -> TapEvent {
    TapEvent(kind: .flagsChanged, keyCode: keyCode, flags: f, isRepeat: false, userData: 0)
  }

  @MainActor
  private final class Harness {
    let monitor: HotkeyMonitor

    private final class Time: @unchecked Sendable { var now: Timestamp = .zero }
    private final class Box: @unchecked Sendable {
      var signals: [DictationSignal] = []
      var cycles = 0
      var cycleEnds = 0
    }
    private let time = Time()
    private let box = Box()

    init(
      config: GestureConfig = GestureConfig(
        primary: .fn,
        languageCycle: .languageCycle)
    ) {
      let time = self.time
      let box = self.box
      monitor = HotkeyMonitor(
        config: config,
        onSignal: { box.signals.append($0) },
        onTapLost: { _ in },
        onGestureAbandoned: {},
        onTapReArmed: {},
        onLanguageCycle: { box.cycles += 1 },
        onLanguageCycleEnded: { box.cycleEnds += 1 },
        clock: { time.now })
    }

    var emitted: [DictationSignal] { box.signals }
    var cycles: Int { box.cycles }
    var cycleEnds: Int { box.cycleEnds }

    func at(_ milliseconds: Int) { time.now = .milliseconds(milliseconds) }
    @discardableResult
    func send(_ event: TapEvent) -> Bool { monitor.consume(event) }
  }

  @Test("holding the record key starts a session and releasing it stops one")
  func holdStartsAndStops() {
    let harness = Harness()
    harness.at(0)
    harness.send(modifier(Code.fn, Bit.fn))
    #expect(harness.emitted == [.start(session: 1)])
    harness.at(600)
    harness.send(modifier(Code.fn, 0))
    #expect(harness.emitted.last == .stop(session: 1, reason: .releasedHold))
  }

  @Test("a second touch is a second recording, never a mode change")
  func aSecondTouchIsASecondRecording() {
    let harness = Harness()
    harness.at(0)
    harness.send(modifier(Code.fn, Bit.fn))
    harness.at(400)
    harness.send(modifier(Code.fn, 0))
    harness.at(500)
    harness.send(modifier(Code.fn, Bit.fn))
    #expect(
      harness.emitted == [
        .start(session: 1),
        .stop(session: 1, reason: .releasedHold),
        .start(session: 2),
      ])
  }

  @Test("a bare modifier is never swallowed — it has to keep working everywhere")
  func theRecordKeyIsNotSwallowed() {
    let harness = Harness()
    #expect(harness.send(modifier(Code.fn, Bit.fn)) == false)
    #expect(harness.send(modifier(Code.fn, 0)) == false)
  }

  @Test("a foreign key while the record key is held cancels the session")
  func foreignKeyCancels() {
    let harness = Harness()
    harness.at(0)
    harness.send(modifier(Code.fn, Bit.fn))
    harness.at(50)
    harness.send(down(Code.a))
    #expect(harness.emitted.last == .cancel(session: 1, reason: .collision))
  }

  @Test("ordinary typing is passed through and starts nothing")
  func typingIsIgnored() {
    let harness = Harness()
    #expect(harness.send(down(Code.a)) == false)
    #expect(harness.send(up(Code.a)) == false)
    #expect(harness.emitted.isEmpty)
  }

  @Test("the app's own synthetic events never reach the machine")
  func syntheticEventsAreIgnored() {
    let harness = Harness()
    let ours = TapEvent(
      kind: .keyDown, keyCode: Code.a, flags: 0, isRepeat: false,
      userData: SyntheticEventSignature.value)
    #expect(harness.send(ours) == false)
    #expect(harness.emitted.isEmpty)
  }

  @Test("our own Command, posted around the paste, does not cancel the session")
  func syntheticModifierDoesNotCancel() {
    let harness = Harness()
    harness.at(0)
    harness.send(modifier(Code.fn, Bit.fn))
    harness.at(50)
    let ours = TapEvent(
      kind: .flagsChanged, keyCode: Code.command,
      flags: Bit.command, isRepeat: false,
      userData: SyntheticEventSignature.value)
    #expect(harness.send(ours) == false)
    #expect(harness.emitted.contains(.cancel(session: 1, reason: .collision)) == false)
  }

  @Test("Esc cancels a live session, and both halves of it are swallowed")
  func escapeCancelsAndIsSwallowed() {
    let harness = Harness()
    harness.at(0)
    harness.send(modifier(Code.fn, Bit.fn))
    harness.at(100)
    #expect(harness.send(down(Code.escape)) == true)
    #expect(harness.emitted.last == .cancel(session: 1, reason: .escape))
    #expect(harness.send(up(Code.escape)) == true)
  }

  @Test("Esc with nothing recording is left alone")
  func escapeAtRestIsPassedThrough() {
    let harness = Harness()
    #expect(harness.send(down(Code.escape)) == false)
    #expect(harness.send(up(Code.escape)) == false)
  }

  @Test("⌃⇧L fires the cycle once and is swallowed in both halves")
  func languageCycleFires() {
    let harness = Harness()
    #expect(harness.send(down(Code.l, flags(Bit.control, Bit.shift))) == true)
    #expect(harness.cycles == 1)
    #expect(harness.send(up(Code.l)) == true)
    #expect(harness.emitted.isEmpty, "the cycle must not open a dictation")
  }

  @Test("auto-repeat is swallowed but does not cycle again")
  func autoRepeatDoesNotCycle() {
    let harness = Harness()
    harness.send(down(Code.l, flags(Bit.control, Bit.shift)))
    for _ in 0..<5 {
      #expect(
        harness.send(
          down(
            Code.l, flags(Bit.control, Bit.shift),
            repeated: true)) == true)
    }
    #expect(harness.cycles == 1)
  }

  @Test("an unclaimed release of the same key is passed through")
  func unclaimedReleaseIsPassedThrough() {
    let harness = Harness()
    #expect(harness.send(up(Code.l)) == false)
  }

  @Test("the record key wins when one chord is bound to both")
  func theRecordKeyWinsOverTheCycle() {
    let harness = Harness(
      config: GestureConfig(
        primary: .languageCycle,
        languageCycle: .languageCycle))
    harness.at(0)
    harness.send(down(Code.l, flags(Bit.control, Bit.shift)))
    #expect(harness.cycles == 0)
    #expect(harness.emitted == [.start(session: 1)])
  }

  @Test("capture reports the peak modifier set once everything is released")
  func captureReportsThePeak() {
    let harness = Harness()
    final class Box: @unchecked Sendable { var captured: CapturedKey? }
    let box = Box()
    harness.monitor.beginCapture(onCapture: { box.captured = $0 }, onCancel: {})

    #expect(harness.send(modifier(Code.control, flags(Bit.control, Bit.leftControl))) == true)
    harness.send(
      modifier(
        Code.option,
        flags(
          Bit.control, Bit.alternate,
          Bit.leftControl, Bit.leftShift)))
    harness.send(modifier(Code.option, 0))
    #expect(
      box.captured
        == CapturedKey(
          keyCode: nil,
          modifiers: [.leftControl, .leftShift]))
    #expect(harness.emitted.isEmpty, "capture must not start a dictation")
  }

  @Test("a capture reports one key — the chord coming back up is not a second")
  func captureReportsOnce() {
    let harness = Harness()
    final class Box: @unchecked Sendable { var captured: [CapturedKey] = [] }
    let box = Box()
    harness.monitor.beginCapture(onCapture: { box.captured.append($0) }, onCancel: {})

    let both = flags(Bit.control, Bit.alternate, Bit.leftControl, Bit.leftOption)
    harness.send(modifier(Code.control, flags(Bit.control, Bit.leftControl)))
    harness.send(modifier(Code.option, both))
    harness.send(down(Code.d, both))
    harness.send(modifier(Code.option, flags(Bit.control, Bit.leftControl)))
    harness.send(modifier(Code.control, 0))

    #expect(
      box.captured == [
        CapturedKey(
          keyCode: Code.d,
          modifiers: [.leftControl, .leftOption])
      ])
  }

  @Test("a cycle key with no modifiers ends its run on its own release")
  func modifierlessCycleEndsOnItsRelease() {
    let f13 = KeyBinding(klass: .functionKey, keyCode: Code.f13, modifiers: [])
    let harness = Harness(config: GestureConfig(primary: .fn, languageCycle: f13))
    #expect(harness.send(down(Code.f13)) == true)
    #expect(harness.cycles == 1)
    #expect(harness.cycleEnds == 0, "the run ended before the key was released")
    #expect(harness.send(up(Code.f13)) == true)
    #expect(harness.cycleEnds == 1)
  }

  @Test("an auto-repeat of a swallowed press survives a change of modifiers")
  func repeatOfAClaimedPressStaysSwallowed() {
    let combo = KeyBinding(
      klass: .comboWithKey, keyCode: Code.d,
      modifiers: [.leftControl, .leftOption])
    let harness = Harness(config: GestureConfig(primary: combo, languageCycle: nil))
    let held = flags(Bit.control, Bit.alternate, Bit.leftControl, Bit.leftOption)
    harness.at(0)
    #expect(harness.send(down(Code.d, held)) == true)
    #expect(harness.emitted == [.start(session: 1)])

    let plusShift = flags(
      Bit.control, Bit.alternate, Bit.shift,
      Bit.leftControl, Bit.leftOption, Bit.leftShift)
    harness.send(modifier(Code.shift, plusShift))
    #expect(
      harness.send(down(Code.d, plusShift, repeated: true)) == true,
      "the repeat typed d into the user's document")
    #expect(harness.emitted == [.start(session: 1)], "and cancelled nothing")

    harness.at(600)
    #expect(harness.send(up(Code.d, plusShift)) == true)
    #expect(harness.emitted.last == .stop(session: 1, reason: .releasedHold))
  }

  @Test("a combo cycle's own release does not end the run")
  func comboCycleSurvivesItsOwnRelease() {
    let harness = Harness()
    let held = flags(Bit.control, Bit.shift, Bit.leftControl, Bit.leftShift)
    harness.send(down(Code.l, held))
    harness.send(up(Code.l, held))
    #expect(harness.cycleEnds == 0)
    harness.send(modifier(Code.control, 0))
    #expect(harness.cycleEnds == 1)
  }

  @Test("the live check sees the candidate's press and release")
  func liveCheckReportsBothHalves() {
    let harness = Harness()
    final class Box: @unchecked Sendable { var events: [LiveCheckEvent] = [] }
    let box = Box()
    harness.monitor.beginLiveCheck(
      of: .fn, onEvent: { box.events.append($0) },
      onCancel: {})
    harness.at(0)
    harness.send(modifier(Code.fn, Bit.fn))
    harness.at(200)
    harness.send(modifier(Code.fn, 0))
    #expect(box.events == [.press(at: .zero), .release(at: .milliseconds(200))])
    #expect(harness.emitted.isEmpty, "a live check must not start a dictation")
  }

  @Test("a key that is not the candidate is left alone during a live check")
  func liveCheckPassesOtherKeysThrough() {
    let harness = Harness()
    harness.monitor.beginLiveCheck(of: .fn, onEvent: { _ in }, onCancel: {})
    #expect(harness.send(down(Code.a)) == false)
  }
}

@Suite("The language status chip follows the held modifiers")
@MainActor
struct LanguageStatusTests {
  @Test("releasing the modifiers ends the run")
  func releaseEndsTheRun() {
    var cycles = 0
    var ends = 0
    let monitor = makeMonitor(
      onLanguageCycle: { cycles += 1 },
      onLanguageCycleEnded: { ends += 1 })
    _ = monitor.consume(cycleKey(down: true))
    _ = monitor.consume(cycleKey(down: false))
    _ = monitor.consume(cycleKey(down: true))
    _ = monitor.consume(cycleKey(down: false))
    #expect(cycles == 2)
    #expect(ends == 0, "the chip came down while the keys were still held")
    _ = monitor.consume(modifiersReleased())
    #expect(ends == 1)
  }

  @Test("modifiers alone start nothing")
  func modifiersAloneDoNothing() {
    var ends = 0
    let monitor = makeMonitor(onLanguageCycle: {}, onLanguageCycleEnded: { ends += 1 })
    _ = monitor.consume(modifiersReleased())
    #expect(ends == 0)
  }

  private func makeMonitor(
    onLanguageCycle: @escaping () -> Void,
    onLanguageCycleEnded: @escaping () -> Void
  ) -> HotkeyMonitor {
    HotkeyMonitor(
      config: .init(
        primary: .fn, languageCycle: .languageCycle,
        timings: .default),
      onSignal: { _ in },
      onTapLost: { _ in },
      onGestureAbandoned: {},
      onTapReArmed: {},
      onLanguageCycle: onLanguageCycle,
      onLanguageCycleEnded: onLanguageCycleEnded)
  }

  private func cycleKey(down: Bool) -> TapEvent {
    TapEvent(
      kind: down ? .keyDown : .keyUp, keyCode: 0x25,
      flags: 0x0006_0000 | 0x03, isRepeat: false, userData: 0)
  }

  private func modifiersReleased() -> TapEvent {
    TapEvent(
      kind: .flagsChanged, keyCode: 59, flags: 0x100,
      isRepeat: false, userData: 0)
  }
}
