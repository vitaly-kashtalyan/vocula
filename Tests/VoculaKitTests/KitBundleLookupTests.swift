import Foundation
import Testing

@Suite("Every kit lookup asks the kit's own bundle")
struct KitBundleLookupTests {
  private static func kitSources() throws -> [(path: String, lines: [String])] {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Sources/VoculaKit")
    let files =
      FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
      .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
    return try files.map {
      (
        path: $0.lastPathComponent,
        lines: SourceScan.logicalLines(try String(contentsOf: $0, encoding: .utf8))
      )
    }
  }

  @Test("the scan reads something")
  func theScanIsNotVacuous() throws {
    let sources = try Self.kitSources()
    #expect(
      sources.count > 20, "found \(sources.count) kit sources — the check would pass on nothing")
    let calls = sources.flatMap(\.lines).filter(Self.isLookup)
    #expect(calls.count > 50, "found \(calls.count) lookups — the check would pass on nothing")
  }

  private static func isLookup(_ line: String) -> Bool {
    (line.contains("String(localized:") || line.contains("LocalizedStringResource("))
      && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
  }

  @Test("no lookup falls back to Bundle.main")
  func everyLookupNamesTheModule() throws {
    for file in try Self.kitSources() {
      for (number, line) in file.lines.enumerated() {
        guard Self.isLookup(line) else { continue }
        var window = line
        for next in file.lines[(number + 1)..<min(number + 8, file.lines.count)] {
          if line.contains("comment:") || Self.isLookup(next) { break }
          window += "\n" + next
          if next.contains("comment:") { break }
        }
        guard !window.contains("bundle: .module"),
          !window.contains("bundle: .atURL(Bundle.module.bundleURL)")
        else { continue }
        let place = "\(file.path):\(number + 1)"
        Issue.record(
          "\(place) looks the key up in Bundle.main, so it renders English in every locale")
      }
    }
  }
}
