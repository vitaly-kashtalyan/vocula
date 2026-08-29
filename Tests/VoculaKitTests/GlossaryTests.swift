import Foundation
import Testing

@Suite("The glossary still describes the copy")
struct GlossaryTests {
  private static var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private static func englishValues() throws -> [String] {
    var values: [String] = []
    for relative in [
      "App/Vocula/Localizable.xcstrings",
      "Sources/VoculaKit/Resources/Localizable.xcstrings",
      "App/Vocula/InfoPlist.xcstrings",
    ] {
      let data = try Data(contentsOf: root.appendingPathComponent(relative))
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
      let strings = json["strings"] as? [String: Any] ?? [:]
      for (_, entry) in strings {
        guard let entry = entry as? [String: Any],
          let locales = entry["localizations"] as? [String: Any],
          let english = locales["en"] as? [String: Any]
        else { continue }
        if let unit = english["stringUnit"] as? [String: Any],
          let value = unit["value"] as? String
        {
          values.append(value)
        }
        if let variations = english["variations"] as? [String: Any],
          let plural = variations["plural"] as? [String: Any]
        {
          for (_, form) in plural {
            if let form = form as? [String: Any],
              let unit = form["stringUnit"] as? [String: Any],
              let value = unit["value"] as? String
            {
              values.append(value)
            }
          }
        }
      }
    }
    return values
  }

  private static func terms() throws -> [String] {
    let text = try String(
      contentsOf: root.appendingPathComponent("Localization/glossary.md"),
      encoding: .utf8)
    let pattern = try NSRegularExpression(pattern: "`([^`]+)`")
    let range = NSRange(text.startIndex..., in: text)
    let symbolic = try NSRegularExpression(pattern: #"^[a-zA-Z]+\.[a-zA-Z.]+$"#)
    var found: [String] = []
    for match in pattern.matches(in: text, range: range) {
      guard let r = Range(match.range(at: 1), in: text) else { continue }
      let term = String(text[r])
      let termRange = NSRange(term.startIndex..., in: term)
      if symbolic.firstMatch(in: term, range: termRange) != nil { continue }
      if term.contains(",") || term.contains("/") || term.contains("*") { continue }
      found.append(term)
    }
    return found
  }

  @Test("the glossary exists and holds terms")
  func theGlossaryIsNotEmpty() throws {
    let terms = try Self.terms()
    #expect(terms.count > 20, "found \(terms.count) terms — the scan read nothing useful")
  }

  @Test("the catalogs were read")
  func theCatalogsWereRead() throws {
    #expect(try Self.englishValues().count > 100)
  }

  private static func haystack() throws -> String {
    var text = try englishValues().joined(separator: "\n")
    for directory in ["Sources", "App/Vocula", "Localization"] {
      let base = root.appendingPathComponent(directory)
      let files =
        FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" || $0.pathExtension == "xcstrings" } ?? []
      for file in files {
        text += "\n" + ((try? String(contentsOf: file, encoding: .utf8)) ?? "")
      }
    }
    return text
  }

  @Test("no glossary term has quietly retired")
  func noTermHasRetired() throws {
    let text = try Self.haystack()
    for term in try Self.terms() {
      #expect(
        text.contains(term),
        "“\(term)” is in the glossary but nowhere in the tree")
    }
  }

  @Test("every appearance of a multi-word term is exactly cased")
  func casingIsConsistent() throws {
    let values = try Self.englishValues()
    for term in try Self.terms() where term.contains(" ") {
      for value in values {
        let lowered = value.lowercased()
        guard lowered.contains(term.lowercased()) else { continue }
        #expect(
          value.contains(term),
          "“\(term)” appears differently cased in: \(value)")
      }
    }
  }
}
