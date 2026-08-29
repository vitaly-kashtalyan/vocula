import Foundation
import Testing

@testable import Vocula

@Suite("The mark's colours stay licensed to the mark")
struct MarkLicenceTests {
  private static let licensed: Set<String> = [
    "markHot", "markCool", "paneSand", "paneHighlight", "paneRamp", "brandRamp",
  ]

  private static func root() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private static func restrictedSymbols() throws -> Set<String> {
    let data = try Data(contentsOf: root().appendingPathComponent("Design/tokens.json"))
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    let colors = json["tokens"] as? [[String: Any]] ?? []
    var symbols: Set<String> = []
    for token in colors where token["use"] != nil {
      guard let name = token["name"] as? String else { continue }
      let parts = name.split(separator: ".")
      guard let first = parts.first else { continue }
      symbols.insert(parts.dropFirst().reduce(String(first)) { $0 + $1.capitalized })
    }
    return symbols
  }

  @Test("the whitelist is read from the designers' file")
  func theLicenceIsNotRestatedHere() throws {
    let symbols = try Self.restrictedSymbols()
    #expect(
      symbols == ["markHot", "markCool"],
      "tokens.json now restricts \(symbols.sorted()) — reconcile the licensed list")
  }

  @Test("no drawing outside the licence reaches for them")
  func onlyLicensedDeclarationsUseTheMark() throws {
    let symbols = try Self.restrictedSymbols()
    let sources =
      FileManager.default.enumerator(
        at: Self.root().appendingPathComponent("App/Vocula"),
        includingPropertiesForKeys: nil)?
      .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
    var checked = 0
    for file in sources where file.lastPathComponent != "ThemeTokens.swift" {
      let lines = try String(contentsOf: file, encoding: .utf8)
        .components(separatedBy: "\n")
      for (number, line) in lines.enumerated() {
        guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//"),
          symbols.contains(where: line.contains)
        else { continue }
        checked += 1
        let owner = lines[...number].reversed().compactMap { candidate -> String? in
          guard
            let range = candidate.range(
              of: #"(static )?let (\w+)"#,
              options: .regularExpression)
          else { return nil }
          return candidate[range].components(separatedBy: " ").last
        }.first
        guard let owner, Self.licensed.contains(owner) else {
          let place = "\(file.lastPathComponent):\(number + 1)"
          let name = owner ?? "something"
          Issue.record(
            "\(place) paints \(name) with the mark's colours, which are licensed to the icon and the strip"
          )
          continue
        }
      }
    }
    #expect(checked >= 4, "found \(checked) references — the scan read almost nothing")
  }
}
