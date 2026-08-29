import CoreGraphics
import Foundation
import VoculaKit

enum KeyNames {
  static func describe(
    _ binding: KeyBinding, locale: Locale = .interface,
    bundle: Bundle = .main
  ) -> String {
    describe(binding, layout: KeyLayout.currentData(), locale: locale, bundle: bundle)
  }

  static func describe(
    _ binding: KeyBinding, layout: Data?,
    locale: Locale = .interface,
    bundle: Bundle = .main
  ) -> String {
    guard let keyCode = binding.keyCode else {
      let sided = sidedNames(binding.modifiers, locale: locale, bundle: bundle)
      return sided.isEmpty
        ? KeyLabels.notSet(locale: locale, bundle: bundle) : sided.joined(separator: " ")
    }
    return glyphs(binding.modifiers)
      + name(of: keyCode, layout: layout, locale: locale, bundle: bundle)
  }

  static func parts(
    _ binding: KeyBinding, locale: Locale = .interface,
    bundle: Bundle = .main
  ) -> [String] {
    parts(binding, layout: KeyLayout.currentData(), locale: locale, bundle: bundle)
  }

  static func parts(
    _ binding: KeyBinding, layout: Data?,
    locale: Locale = .interface,
    bundle: Bundle = .main
  ) -> [String] {
    guard let keyCode = binding.keyCode else {
      let sided = sidedNames(binding.modifiers, locale: locale, bundle: bundle)
      return sided.isEmpty ? [KeyLabels.notSet(locale: locale, bundle: bundle)] : sided
    }
    return glyphParts(binding.modifiers) + [
      name(of: keyCode, layout: layout, locale: locale, bundle: bundle)
    ]
  }

  static func name(
    of keyCode: UInt16, layout: Data?,
    locale: Locale = .interface,
    bundle: Bundle = .main
  ) -> String {
    if let symbol = KeyLayout.symbols[keyCode] { return symbol }
    if let label = KeyLabels.named(keyCode, locale: locale, bundle: bundle) { return label }
    if let layout, let typed = KeyLayout.character(for: CGKeyCode(keyCode), in: layout),
      let scalar = typed.unicodeScalars.first,
      !CharacterSet.whitespacesAndNewlines.contains(scalar),
      !CharacterSet.controlCharacters.contains(scalar)
    {
      return typed.uppercased()
    }
    return KeyLabels.unknown(keyCode, locale: locale, bundle: bundle)
  }

  private static func glyphs(_ modifiers: ModifierSet) -> String {
    glyphParts(modifiers).joined()
  }

  private static func glyphParts(_ modifiers: ModifierSet) -> [String] {
    let glyph = KeyLayout.modifierGlyphs
    var parts: [String] = []
    if modifiers.contains(.function) { parts.append(glyph.function) }
    if !modifiers.isDisjoint(with: [.leftControl, .rightControl]) { parts.append(glyph.control) }
    if !modifiers.isDisjoint(with: [.leftOption, .rightOption]) { parts.append(glyph.option) }
    if !modifiers.isDisjoint(with: [.leftShift, .rightShift]) { parts.append(glyph.shift) }
    if !modifiers.isDisjoint(with: [.leftCommand, .rightCommand]) { parts.append(glyph.command) }
    return parts
  }

  private static func sidedNames(_ modifiers: ModifierSet, locale: Locale, bundle: Bundle)
    -> [String]
  {
    let glyph = KeyLayout.modifierGlyphs
    var parts: [String] = []
    if modifiers.contains(.function) { parts.append(glyph.function) }
    if modifiers.contains(.leftControl) {
      parts.append(KeyLabels.left(glyph.control, locale: locale, bundle: bundle))
    }
    if modifiers.contains(.rightControl) {
      parts.append(KeyLabels.right(glyph.control, locale: locale, bundle: bundle))
    }
    if modifiers.contains(.leftOption) {
      parts.append(KeyLabels.left(glyph.option, locale: locale, bundle: bundle))
    }
    if modifiers.contains(.rightOption) {
      parts.append(KeyLabels.right(glyph.option, locale: locale, bundle: bundle))
    }
    if modifiers.contains(.leftShift) {
      parts.append(KeyLabels.left(glyph.shift, locale: locale, bundle: bundle))
    }
    if modifiers.contains(.rightShift) {
      parts.append(KeyLabels.right(glyph.shift, locale: locale, bundle: bundle))
    }
    if modifiers.contains(.leftCommand) {
      parts.append(KeyLabels.left(glyph.command, locale: locale, bundle: bundle))
    }
    if modifiers.contains(.rightCommand) {
      parts.append(KeyLabels.right(glyph.command, locale: locale, bundle: bundle))
    }
    return parts
  }
}
