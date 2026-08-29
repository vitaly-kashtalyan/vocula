import Testing

@testable import VoculaKit

private enum Bit {
  static let shift: UInt64 = 0x0002_0000
  static let control: UInt64 = 0x0004_0000
  static let alternate: UInt64 = 0x0008_0000
  static let command: UInt64 = 0x0010_0000
  static let fn: UInt64 = 0x0080_0000

  static let leftControl: UInt64 = 0x0000_0001
  static let leftShift: UInt64 = 0x0000_0002
  static let rightShift: UInt64 = 0x0000_0004
  static let leftCommand: UInt64 = 0x0000_0008
  static let rightCommand: UInt64 = 0x0000_0010
  static let leftOption: UInt64 = 0x0000_0020
  static let rightOption: UInt64 = 0x0000_0040
  static let rightControl: UInt64 = 0x0000_2000
}

private enum Code {
  static let leftCommand: UInt16 = 0x37
  static let rightCommand: UInt16 = 0x36
  static let leftControl: UInt16 = 0x3B
  static let leftOption: UInt16 = 0x3A
  static let fn: UInt16 = 0x3F
  static let d: UInt16 = 0x02
  static let f13: UInt16 = 0x69
}

private func or(_ bits: UInt64...) -> UInt64 { bits.reduce(0, |) }

private let controlOption = KeyBinding(
  klass: .modifierPair, keyCode: nil,
  modifiers: [.leftControl, .leftOption])
private let controlOptionD = KeyBinding(
  klass: .comboWithKey, keyCode: Code.d,
  modifiers: [.leftControl, .leftOption])
private let f13 = KeyBinding(klass: .functionKey, keyCode: Code.f13, modifiers: [])

@Suite("Key matching")
struct KeyMatchingTests {
  @Test("a held left ⌘ does not make the right ⌘ read as down")
  func sidesAreNotConfused() {
    let leftHeldRightUp = or(Bit.command, Bit.leftCommand)
    #expect(KeyMatching.isDown(Code.leftCommand, in: leftHeldRightUp) == true)
    #expect(KeyMatching.isDown(Code.rightCommand, in: leftHeldRightUp) == false)
  }

  @Test("Fn has no side, so it is read from the coarse mask")
  func fnIsReadFromTheCoarseMask() {
    #expect(KeyMatching.isDown(Code.fn, in: Bit.fn) == true)
    #expect(KeyMatching.isDown(Code.fn, in: 0) == false)
  }

  @Test("every modifier down is reported with its side")
  func sidedModifiersReportsSides() {
    let flags = or(Bit.command, Bit.rightCommand, Bit.control, Bit.leftControl, Bit.fn)
    #expect(
      KeyMatching.sidedModifiers(in: flags)
        == [.rightCommand, .leftControl, .function])
  }

  @Test("Fn matches its own flagsChanged and nothing else")
  func fnMatchesFlagsChanged() {
    let down = RawKeyEvent(kind: .flagsChanged, keyCode: Code.fn, flags: Bit.fn)
    #expect(KeyMatching.matchesShape(.fn, down) == true)
    #expect(KeyMatching.isPress(down) == true)

    let up = RawKeyEvent(kind: .flagsChanged, keyCode: Code.fn, flags: 0)
    #expect(KeyMatching.matchesShape(.fn, up) == true)
    #expect(KeyMatching.isPress(up) == false)

    let typing = RawKeyEvent(kind: .keyDown, keyCode: Code.d, flags: 0)
    #expect(KeyMatching.matchesShape(.fn, typing) == false)
  }

  @Test("a pair does not fire on one of its two modifiers")
  func pairNeedsBothOnPress() {
    let controlOnly = RawKeyEvent(
      kind: .flagsChanged, keyCode: Code.leftControl,
      flags: or(Bit.control, Bit.leftControl))
    #expect(KeyMatching.matchesShape(controlOption, controlOnly) == false)

    let bothDown = RawKeyEvent(
      kind: .flagsChanged, keyCode: Code.leftOption,
      flags: or(Bit.control, Bit.leftControl, Bit.alternate, Bit.leftOption))
    #expect(KeyMatching.matchesShape(controlOption, bothDown) == true)
    #expect(KeyMatching.isPress(bothDown) == true)
  }

  @Test("a pair's release matches on membership alone")
  func pairReleaseMatchesOnMembership() {
    let controlUpOptionStillDown = RawKeyEvent(
      kind: .flagsChanged, keyCode: Code.leftControl,
      flags: or(Bit.alternate, Bit.leftOption))
    #expect(KeyMatching.matchesShape(controlOption, controlUpOptionStillDown) == true)
    #expect(KeyMatching.isPress(controlUpOptionStillDown) == false)
  }

  @Test("a modifier that is not part of the pair never matches")
  func foreignModifierNeverMatches() {
    let command = RawKeyEvent(
      kind: .flagsChanged, keyCode: Code.leftCommand,
      flags: or(Bit.command, Bit.leftCommand))
    #expect(KeyMatching.matchesShape(controlOption, command) == false)
  }

  @Test("a combo's press must carry exactly its modifiers")
  func comboPressNeedsItsModifiers() {
    let correct = RawKeyEvent(
      kind: .keyDown, keyCode: Code.d,
      flags: or(Bit.control, Bit.alternate))
    #expect(KeyMatching.matchesShape(controlOptionD, correct) == true)

    let bare = RawKeyEvent(kind: .keyDown, keyCode: Code.d, flags: 0)
    #expect(KeyMatching.matchesShape(controlOptionD, bare) == false)

    let extra = RawKeyEvent(
      kind: .keyDown, keyCode: Code.d,
      flags: or(Bit.control, Bit.alternate, Bit.command))
    #expect(KeyMatching.matchesShape(controlOptionD, extra) == false)
  }

  @Test("a combo's release matches on the key code alone")
  func comboReleaseMatchesOnKeyCodeAlone() {
    let bareRelease = RawKeyEvent(kind: .keyUp, keyCode: Code.d, flags: 0)
    #expect(KeyMatching.matchesShape(controlOptionD, bareRelease) == true)
    #expect(KeyMatching.isPress(bareRelease) == false)
  }

  @Test("a function key matches by its code, with no modifiers")
  func functionKeyMatches() {
    #expect(
      KeyMatching.matchesShape(
        f13, RawKeyEvent(kind: .keyDown, keyCode: Code.f13, flags: 0)) == true)
    #expect(
      KeyMatching.matchesShape(
        f13, RawKeyEvent(kind: .keyDown, keyCode: Code.d, flags: 0)) == false)
  }

  @Test("the record key is matched by shape, and nothing else is")
  func recordKeyIsMatchedByShape() {
    let config = GestureConfig(primary: .fn)
    let fnDown = RawKeyEvent(kind: .flagsChanged, keyCode: Code.fn, flags: Bit.fn)
    let comboDown = RawKeyEvent(
      kind: .keyDown, keyCode: Code.d,
      flags: or(Bit.control, Bit.alternate))
    let typing = RawKeyEvent(kind: .keyDown, keyCode: 0x00, flags: 0)
    #expect(KeyMatching.matchesPrimary(config: config, event: fnDown))
    #expect(KeyMatching.matchesPrimary(config: config, event: comboDown) == false)
    #expect(KeyMatching.matchesPrimary(config: config, event: typing) == false)
  }

  @Test("Fn is pollable, and a binding with no modifiers is not")
  func pollMaskIsNilOnlyWhenNothingCanBePolled() {
    #expect(KeyMatching.pollMask(for: .fn) == Bit.fn)
    #expect(KeyMatching.pollMask(for: f13) == nil)
    #expect(KeyMatching.pollMask(for: controlOption) == or(Bit.control, Bit.alternate))
  }

  @Test("a clear coarse mask proves the binding is up")
  func coarseMaskClearMeansUp() {
    #expect(KeyMatching.isBindingHeld(.fn, flags: 0) == false)
    #expect(KeyMatching.isBindingHeld(.fn, flags: Bit.fn) == true)
  }

  @Test("with the coarse mask set, the sided bit decides")
  func sidedBitDecidesWhenPublished() {
    let leftDown = or(Bit.command, Bit.leftCommand)
    #expect(KeyMatching.isBindingHeld(.rightCommand, flags: leftDown) == false)
    let rightDown = or(Bit.command, Bit.rightCommand)
    #expect(KeyMatching.isBindingHeld(.rightCommand, flags: rightDown) == true)
  }

  @Test("a source that publishes no device bits falls back to the coarse mask")
  func degradesWhenNoDeviceBitsArePublished() {
    #expect(KeyMatching.isBindingHeld(.rightCommand, flags: Bit.command) == true)
  }

  @Test("a binding with no pollable mask is never held")
  func unpollableBindingIsNeverHeld() {
    #expect(KeyMatching.isBindingHeld(f13, flags: 0xFFFF_FFFF) == false)
  }
}

@Suite("Language cycle matching")
struct LanguageCycleMatchingTests {
  private let l: UInt16 = 0x25
  private let config = GestureConfig(primary: .fn, languageCycle: .languageCycle)

  private func press(_ keyCode: UInt16, _ flags: UInt64) -> RawKeyEvent {
    RawKeyEvent(kind: .keyDown, keyCode: keyCode, flags: flags)
  }

  @Test("⌃⇧L matches the language cycle")
  func matches() {
    #expect(
      KeyMatching.matchesLanguageCycle(
        config: config, event: press(l, or(Bit.control, Bit.shift))))
  }

  @Test("either side of ⌃⇧ matches: a combo is compared side-agnostically")
  func eitherSide() {
    #expect(
      KeyMatching.matchesLanguageCycle(
        config: config,
        event: press(l, or(Bit.control, Bit.shift, Bit.rightControl, Bit.rightShift))))
  }

  @Test("L without the modifiers is just typing")
  func bareLetter() {
    #expect(KeyMatching.matchesLanguageCycle(config: config, event: press(l, 0)) == false)
  }

  @Test("a different key with the same modifiers does not match")
  func otherKey() {
    #expect(
      KeyMatching.matchesLanguageCycle(
        config: config, event: press(Code.d, or(Bit.control, Bit.alternate))) == false)
  }

  @Test("without a language-cycle binding nothing matches")
  func noBinding() {
    #expect(
      KeyMatching.matchesLanguageCycle(
        config: GestureConfig(primary: .fn),
        event: press(l, or(Bit.control, Bit.alternate))) == false)
  }

  @Test("the record key wins when both are bound to the same chord")
  func recordKeyWins() {
    let clash = GestureConfig(primary: .languageCycle, languageCycle: .languageCycle)
    let event = press(l, or(Bit.control, Bit.shift))
    #expect(KeyMatching.matchesPrimary(config: clash, event: event))
    #expect(KeyMatching.matchesLanguageCycle(config: clash, event: event) == false)
  }

  @Test("the release matches the shape too, so it can be swallowed in pairs")
  func releaseMatchesShape() {
    #expect(
      KeyMatching.matchesLanguageCycle(
        config: config, event: RawKeyEvent(kind: .keyUp, keyCode: l, flags: 0)))
  }
}
