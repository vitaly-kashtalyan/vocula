import AppKit
import Testing

@testable import Vocula

@MainActor
struct IndicatorChipSizeTests {
  private let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)

  @Test("short notes share one width, so switching does not resize")
  func shortNotesDoNotResize() {
    let names = ["Español", "English", "Auto", "Deutsch", "日本語"]
    let widths = Set(names.map { IndicatorPanel.chipSize(for: $0, on: screen).0 })
    #expect(widths.count == 1, "language names came out \(widths.count) different widths")
  }

  @Test("a longer message gets a wider chip")
  func growsWithTheText() {
    let short = IndicatorPanel.chipSize(for: "Español", on: screen).0
    let long = IndicatorPanel.chipSize(
      for: "Your microphone's input volume is turned all the way down.",
      on: screen
    ).0
    #expect(long > short)
  }

  @Test("the real messages fit on one line's height")
  func realMessagesFit() {
    for text in [
      "Your microphone's input volume is turned all the way down, so the "
        + "recording was silent. Raise it in System Settings → Sound → Input.",
      "Nothing was inserted.",
    ] {
      let (width, _) = IndicatorPanel.chipSize(for: text, on: screen)
      #expect(width <= screen.width / 2)
    }
  }

  @Test("a runaway message is bounded")
  func boundsARunawayMessage() {
    let (width, height) = IndicatorPanel.chipSize(
      for: String(repeating: "diagnostic ", count: 400), on: screen)
    #expect(width <= screen.width / 2)
    #expect(height < 120)
  }

  @Test("a line is counted as a line")
  func oneLineIsOneLine() {
    #expect(IndicatorPanel.naturalLines(for: "Nothing was inserted.", on: screen) == 1)
    #expect(
      IndicatorPanel.naturalLines(
        for: "Your microphone's input volume is turned all the way down, so the "
          + "recording was silent. Raise it in System Settings → Sound → Input.",
        on: screen) == 2)
  }

  private static func reachesTheChip(_ key: String) -> Bool {
    key.hasPrefix("refusal.") || key.hasPrefix("indicator.")
      || key == "languages.auto.short"
  }

  @Test("no translated refusal is cut off by the three-line cap")
  func translatedRefusalsFitTheChip() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    var checked = 0
    var sawLanguageHUD = false
    for relative in [
      "Sources/VoculaKit/Resources/Localizable.xcstrings",
      "App/Vocula/Localizable.xcstrings",
    ] {
      let data = try Data(contentsOf: root.appendingPathComponent(relative))
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
      let strings = json["strings"] as? [String: Any] ?? [:]
      for (key, entry) in strings where Self.reachesTheChip(key) {
        guard let entry = entry as? [String: Any],
          let locales = entry["localizations"] as? [String: Any]
        else { continue }
        for (language, localization) in locales {
          guard let localization = localization as? [String: Any],
            let unit = localization["stringUnit"] as? [String: Any],
            let value = unit["value"] as? String
          else { continue }
          checked += 1
          if key == "languages.auto.short" { sawLanguageHUD = true }
          let lines = IndicatorPanel.naturalLines(for: value, on: screen)
          #expect(
            lines <= IndicatorPanel.maxChipLines,
            "\(key) [\(language)] wants \(lines) lines and would be cut off")
        }
      }
    }
    #expect(checked > 20, "the scan read \(checked) values — it checked almost nothing")
    #expect(sawLanguageHUD, "the ⌃⇧L language label was not among the values scanned")
  }
}
