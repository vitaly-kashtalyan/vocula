import Carbon.HIToolbox
import Foundation
import Testing
import VoculaKit

@testable import Vocula

struct KeyNamesTests {
  private let english = Locale(identifier: "en")
  private let englishBundle: Bundle = {
    let path = Bundle.main.path(forResource: "en", ofType: "lproj")
    return path.flatMap(Bundle.init(path:)) ?? .main
  }()

  private let ansi = installedLayoutData("com.apple.keylayout.ABC")

  @Test("a single modifier is named, with its side")
  func singleModifiers() {
    #expect(KeyNames.describe(.fn, layout: ansi, locale: english, bundle: englishBundle) == "fn")
    #expect(
      KeyNames.describe(.rightCommand, layout: ansi, locale: english, bundle: englishBundle)
        == "right ⌘")
    #expect(
      KeyNames.describe(.rightOption, layout: ansi, locale: english, bundle: englishBundle)
        == "right ⌥")
  }

  @Test("a pair keeps both sides, because the pair is matched by key code")
  func pairs() {
    let pair = KeyBinding(
      klass: .modifierPair, keyCode: nil,
      modifiers: [.leftControl, .leftOption])
    #expect(
      KeyNames.describe(pair, layout: ansi, locale: english, bundle: englishBundle)
        == "left ⌃ left ⌥")
  }

  @Test("the default language cycle prints as ⌃⇧L on an ANSI layout")
  func languageCycleOnAnsi() throws {
    let data = try #require(ansi, "ABC is not installed")
    #expect(
      KeyNames.describe(.languageCycle, layout: data, locale: english, bundle: englishBundle)
        == "⌃⇧L")
  }

  @Test("under Dvorak the same position prints the character Dvorak types")
  func languageCycleOnDvorak() throws {
    let data = try #require(
      installedLayoutData("com.apple.keylayout.Dvorak"),
      "Dvorak is not installed")
    #expect(
      KeyNames.describe(.languageCycle, layout: data, locale: english, bundle: englishBundle)
        == "⌃⇧N")
  }

  @Test("function keys are named by number, not by whatever they type")
  func functionKeys() {
    let f13 = KeyBinding(klass: .functionKey, keyCode: 0x69, modifiers: [])
    #expect(KeyNames.describe(f13, layout: ansi, locale: english, bundle: englishBundle) == "F13")
  }

  @Test("keys that type nothing readable have names of their own")
  func namedKeys() {
    let space = KeyBinding(
      klass: .comboWithKey, keyCode: 0x31,
      modifiers: [.leftControl, .leftOption])
    #expect(
      KeyNames.describe(space, layout: ansi, locale: english, bundle: englishBundle) == "⌃⌥Space")
  }

  @Test("an unknown key code is shown as a code, never as an invented letter")
  func unknownKey() {
    let odd = KeyBinding(
      klass: .comboWithKey, keyCode: 0x7F,
      modifiers: [.leftCommand])
    #expect(
      KeyNames.describe(odd, layout: nil, locale: english, bundle: englishBundle) == "⌘key 127")
  }

  @Test("a chord splits into one part per cap, and joins back to the same string")
  func chordParts() throws {
    let data = try #require(ansi, "ABC is not installed")
    #expect(
      KeyNames.parts(.languageCycle, layout: data, locale: english, bundle: englishBundle) == [
        "⌃", "⇧", "L",
      ])
    #expect(
      KeyNames.parts(.languageCycle, layout: data, locale: english, bundle: englishBundle).joined()
        == KeyNames.describe(.languageCycle, layout: data, locale: english, bundle: englishBundle))
  }

  @Test("a bare modifier is one cap, and an unset binding says so rather than being empty")
  func modifierParts() {
    #expect(KeyNames.parts(.fn, layout: ansi, locale: english, bundle: englishBundle) == ["fn"])
    let pair = KeyBinding(
      klass: .modifierPair, keyCode: nil,
      modifiers: [.leftControl, .leftOption])
    #expect(
      KeyNames.parts(pair, layout: ansi, locale: english, bundle: englishBundle) == [
        "left ⌃", "left ⌥",
      ])
    let none = KeyBinding(klass: .modifierPair, keyCode: nil, modifiers: [])
    #expect(
      KeyNames.parts(none, layout: ansi, locale: english, bundle: englishBundle) == ["not set"])
  }

  @Test("modifiers are printed in the order macOS uses: ⌃⌥⇧⌘")
  func modifierOrder() {
    let all = KeyBinding(
      klass: .comboWithKey, keyCode: 0x02,
      modifiers: [
        .rightCommand, .leftShift,
        .leftOption, .leftControl,
      ])
    #expect(KeyNames.describe(all, layout: ansi, locale: english, bundle: englishBundle) == "⌃⌥⇧⌘D")
  }
}
