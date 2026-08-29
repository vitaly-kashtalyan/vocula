import Foundation
import Testing

@testable import Vocula

private func relativeLuminance(_ hex: UInt32) -> Double {
  func channel(_ raw: UInt32) -> Double {
    let value = Double(raw) / 255
    return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * channel((hex >> 16) & 0xFF)
    + 0.7152 * channel((hex >> 8) & 0xFF)
    + 0.0722 * channel(hex & 0xFF)
}

private func contrast(_ ink: UInt32, on surface: UInt32) -> Double {
  let a = relativeLuminance(ink)
  let b = relativeLuminance(surface)
  return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

private struct Pairing {
  let name: String
  let ink: UInt32
  let surface: UInt32
}

private let surfaces: [(String, UInt32, UInt32)] = [
  ("window", Theme.Ink.windowLight, Theme.Ink.windowDark),
  ("card", Theme.Ink.cardLight, Theme.Ink.cardDark),
]

private func pairings(_ role: String, light: UInt32, dark: UInt32) -> [Pairing] {
  surfaces.flatMap { name, surfaceLight, surfaceDark in
    [
      Pairing(name: "\(role) on \(name), light", ink: light, surface: surfaceLight),
      Pairing(name: "\(role) on \(name), dark", ink: dark, surface: surfaceDark),
    ]
  }
}

@Suite("Text roles against the surfaces they are drawn on")
struct ThemeContrastTests {
  private static let aa = 4.5

  private static let readable =
    pairings(
      "textPrimary", light: Theme.Tokens.textPrimaryLight,
      dark: Theme.Tokens.textPrimaryDark)
    + pairings(
      "textSecondary", light: Theme.Tokens.textSecondaryLight,
      dark: Theme.Tokens.textSecondaryDark)
    + pairings("warning", light: Theme.Ink.warningLight, dark: Theme.Ink.warningDark)

  private static let muted =
    pairings(
      "textMuted", light: Theme.Tokens.textMutedLight,
      dark: Theme.Tokens.textMutedDark)

  @Test("the roles that carry ordinary text reach AA")
  func readableRolesReachAA() {
    #expect(Self.readable.count == 12, "the sweep would pass on nothing")
    for pairing in Self.readable {
      let measured = contrast(pairing.ink, on: pairing.surface)
      #expect(
        measured >= Self.aa,
        "\(pairing.name) is \(String(format: "%.2f", measured)):1")
    }
  }

  @Test("textMuted still fails AA, and the numbers have not moved")
  func mutedStillFails() {
    let measured = Self.muted.map { contrast($0.ink, on: $0.surface) }
    let expected = [3.16, 5.12, 3.51, 4.19]
    #expect(measured.count == expected.count)
    for (index, value) in measured.enumerated() {
      #expect(
        abs(value - expected[index]) < 0.01,
        "\(Self.muted[index].name) is now \(String(format: "%.2f", value)):1")
    }
    #expect(
      measured.filter { $0 < Self.aa }.count == 3,
      "textMuted no longer fails three of four — retire this test")
  }
}
