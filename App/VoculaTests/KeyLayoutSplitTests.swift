import Foundation
import Testing

@testable import Vocula

@Suite("KeyNames is two halves")
struct KeyLayoutSplitTests {
  private let english = Locale(identifier: "en")
  private let englishBundle: Bundle = {
    let path = Bundle.main.path(forResource: "en", ofType: "lproj")
    return path.flatMap(Bundle.init(path:)) ?? .main
  }()

  private static func source(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Vocula/Hotkey/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
      .replacingOccurrences(
        of: #"\(\s*\n\s*"#, with: "(", options: .regularExpression)
  }

  @Test("the scan reads the files it claims to")
  func theScanIsNotVacuous() throws {
    #expect(try Self.source("KeyLayout.swift").contains("UCKeyTranslate"))
    #expect(try Self.source("KeyLabels.swift").contains("String(localized:"))
  }

  @Test("the layout half carries no copy")
  func layoutHalfHasNoStrings() throws {
    #expect(!(try Self.source("KeyLayout.swift").contains("String(localized:")))
  }

  @Test("the labels half never reads a layout")
  func labelsHalfTouchesNoLayout() throws {
    let labels = try Self.source("KeyLabels.swift")
    #expect(!labels.contains("UCKeyTranslate"))
    #expect(!labels.contains("TISCopy"))
    #expect(!labels.contains("KeyLayout."), "the labels half called into the layout half")
  }

  @Test("each half is usable without the other")
  func halvesAreReachableSeparately() {
    #expect(KeyLabels.named(0x31, locale: english, bundle: englishBundle) == "Space")
    #expect(
      KeyLabels.named(0x7B, locale: english, bundle: englishBundle) == nil,
      "an arrow is a glyph and belongs to the layout half")
    #expect(KeyLayout.symbols[0x7B] == "←")
    #expect(KeyLayout.symbols[0x31] == nil, "the space bar's name is a word, not a glyph")
  }

  @Test("a typed character is still cased by the layout, not by a fixed locale")
  func typedCharactersKeepLayoutCasing() throws {
    let layout = try #require(KeyLayout.currentData())
    #expect(KeyLayout.character(for: 0x00, in: layout) != nil)
  }
}
