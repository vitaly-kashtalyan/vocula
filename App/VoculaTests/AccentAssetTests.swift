import AppKit
import Testing

@testable import Vocula

@Suite("Accent asset")
struct AccentAssetTests {
  private func hex(_ colour: NSColor) -> UInt32 {
    let c = colour.usingColorSpace(.sRGB) ?? colour
    let r = UInt32((c.redComponent * 255).rounded())
    let g = UInt32((c.greenComponent * 255).rounded())
    let b = UInt32((c.blueComponent * 255).rounded())
    return r << 16 | g << 8 | b
  }

  @Test(
    "the catalog's accent is the same brass as Theme.Ink",
    arguments: [
      (NSAppearance.Name.aqua, Theme.Ink.fillLight),
      (NSAppearance.Name.darkAqua, Theme.Ink.fillDark),
    ])
  func matchesInk(_ name: NSAppearance.Name, _ expected: UInt32) throws {
    let asset = try #require(
      NSColor(named: "AccentColor"),
      "AccentColor is missing from the asset catalog")
    let appearance = try #require(NSAppearance(named: name))
    var resolved: UInt32 = 0
    appearance.performAsCurrentDrawingAppearance { resolved = hex(asset) }
    let got = String(format: "#%06X", resolved)
    let want = String(format: "#%06X", expected)
    #expect(resolved == expected, "catalog has \(got) where Theme.Ink says \(want)")
  }
}
