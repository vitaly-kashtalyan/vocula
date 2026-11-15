import Foundation
import Testing

@Suite("Every place that names Sparkle's version names the same one")
struct SparkleVersionTests {
  private static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  private static func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }

  private static func versions(in text: String, after marker: String) -> [String] {
    text.components(separatedBy: marker).dropFirst().compactMap { tail in
      let digits = tail.prefix { $0.isNumber || $0 == "." }
      return digits.contains(".") ? String(digits) : nil
    }
  }

  @Test("the workflow, the notice, the licence link and the placement rule agree")
  func spellingsAgree() throws {
    let sources = [
      "the workflow": Self.versions(
        in: try Self.read(".github/workflows/release.yml"),
        after: "sparkle-project/Sparkle/releases/download/"),
      "the notice": Self.versions(
        in: try Self.read("App/Vocula/UI/ModelPickerView.swift"), after: "Sparkle "),
      "the licence link": Self.versions(
        in: try Self.read("App/Vocula/Licenses/THIRD-PARTY.txt"),
        after: "sparkle-project/Sparkle/blob/"),
      "the placement rule": Self.versions(
        in: try Self.read("Tests/VoculaKitTests/InstallPlacementTests.swift"), after: "Sparkle "),
    ]

    for (source, versions) in sources {
      #expect(
        !versions.isEmpty, "\(source) names no Sparkle version — the marker moved, not the version")
    }
    let found = Set(sources.values.joined())
    #expect(found.count == 1, "Sparkle is named as \(found.sorted())")
  }

  @Test("the package is pinned by a revision, which a tag cannot satisfy")
  func pinnedByRevision() throws {
    let line = try Self.read("App/project.yml")
      .split(separator: "\n")
      .first { $0.contains("    revision:") }
    let revision = line?
      .replacingOccurrences(of: "    revision:", with: "")
      .trimmingCharacters(in: .whitespaces)
    #expect(revision?.count == 40)
    #expect(revision?.allSatisfy(\.isHexDigit) == true)
  }
}
