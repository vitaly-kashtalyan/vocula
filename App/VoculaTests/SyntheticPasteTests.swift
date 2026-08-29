import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing

@testable import Vocula

struct SyntheticPasteTests {
  @Test("V is the ANSI position on layouts that keep it there")
  func ansiLayoutsResolveToTheAnsiPosition() throws {
    for id in [
      "com.apple.keylayout.ABC", "com.apple.keylayout.US",
      "com.apple.keylayout.German", "com.apple.keylayout.Colemak",
    ] {
      let data = try #require(installedLayoutData(id), "\(id) is not installed")
      #expect(SyntheticPaste.keyCode(for: "v", in: data) == CGKeyCode(kVK_ANSI_V))
    }
  }

  @Test("Dvorak resolves V to its own position, not the ANSI one")
  func dvorakResolvesToItsOwnPosition() throws {
    let data = try #require(
      installedLayoutData("com.apple.keylayout.Dvorak"),
      "Dvorak is not installed")
    let resolved = SyntheticPaste.keyCode(for: "v", in: data)
    #expect(resolved == 0x2f)
    #expect(resolved != CGKeyCode(kVK_ANSI_V))
  }

  @Test("a layout with no V yields no answer rather than a wrong key")
  func nonAsciiLayoutYieldsNothing() throws {
    let data = try #require(
      installedLayoutData("com.apple.keylayout.Greek"),
      "Greek is not installed")
    #expect(SyntheticPaste.keyCode(for: "v", in: data) == nil)
  }
}

@Suite("The paste chord")
struct PasteChordTests {
  @Test("Command goes down before the key and up after it")
  func chordBracketsTheKey() {
    let key = CGKeyCode(kVK_ANSI_V)
    let command = CGKeyCode(kVK_Command)
    let steps = SyntheticPaste.chord(for: key, whileHolding: [])
    #expect(steps.map(\.key) == [command, key, key, command])
    #expect(steps.map(\.isDown) == [true, true, false, false])
  }

  @Test("the key carries Command and nothing else, and the release clears it")
  func chordCarriesOnlyCommand() {
    let steps = SyntheticPaste.chord(for: CGKeyCode(kVK_ANSI_V), whileHolding: [])
    #expect(steps.dropLast().allSatisfy { $0.flags == .maskCommand })
    #expect(steps.last?.flags == [])
  }

  @Test("a modifier the user is holding survives the chord")
  func chordPreservesOtherModifiers() {
    let steps = SyntheticPaste.chord(for: CGKeyCode(kVK_ANSI_V), whileHolding: .maskShift)
    #expect(steps.first?.flags == [.maskShift, .maskCommand])
    #expect(steps.last?.flags == .maskShift)
  }

  @Test("a Command the user is already holding is never released under them")
  func chordLeavesAHeldCommandAlone() {
    let key = CGKeyCode(kVK_ANSI_V)
    let steps = SyntheticPaste.chord(for: key, whileHolding: .maskCommand)
    #expect(steps.map(\.key) == [key, key])
    #expect(steps.allSatisfy { $0.flags == .maskCommand })
  }
}
