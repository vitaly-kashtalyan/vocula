import Foundation
import Testing

@Suite("No user-facing sentence is written as a bare literal")
struct UnlocalizedProseTests {
  private static let safeContext = [
    "accessibilityIdentifier", "systemImage", "systemName", "Image(", "forKey",
    "identifier:", "key:", ".font", "UserDefaults", "suiteName", "comment:",
    "defaultValue:", "String(localized:", "LocalizedStringResource(", "bundle",
    "table:", "#", "NSSound", "appendingPathComponent", "pathExtension", "URL(",
    "domain", "rawValue",
    "precondition", "assertionFailure", "fatalError", "preconditionFailure",
  ]

  private static let deliberateEnglish = [
    "System Settings → Privacy & Security",
    "System Settings → Privacy & Security → Microphone",
    "System Settings → Privacy & Security → Accessibility",
    "System Settings → General → Login Items & Extensions",
    "System Settings → Keyboard → Press 🌐 key to",
    "System Settings → Screen Time → Content & Privacy",
    "Unknown device",
    "Built-in Microphone",
    "the system default microphone",
  ]

  private static let dataOnlyFiles: Set<String> = [
    "ModelManifest.swift",
    "StopPhrases.swift",
  ]

  private static func appSources() throws -> [(path: String, lines: [String])] {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let files = ["App/Vocula", "Sources/VoculaKit"].flatMap { relative in
      FileManager.default.enumerator(
        at: root.appendingPathComponent(relative),
        includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
    }
    return try files.map {
      (
        path: $0.lastPathComponent,
        lines: SourceScan.logicalLines(try String(contentsOf: $0, encoding: .utf8))
      )
    }
  }

  private static func literals(in line: String) -> [String] {
    var found: [String] = []
    var current: String?
    for character in line {
      if character == "\"" {
        if let value = current {
          found.append(value)
          current = nil
        } else {
          current = ""
        }
      } else if current != nil {
        current?.append(character)
      }
    }
    return found
  }

  private static func withoutInterpolations(_ value: String) -> String {
    var result = ""
    var depth = 0
    var index = value.startIndex
    while index < value.endIndex {
      let character = value[index]
      if depth == 0, character == "\\", value.index(after: index) < value.endIndex,
        value[value.index(after: index)] == "("
      {
        depth = 1
        index = value.index(index, offsetBy: 2)
        continue
      }
      if depth > 0 {
        if character == "(" { depth += 1 }
        if character == ")" { depth -= 1 }
        index = value.index(after: index)
        continue
      }
      result.append(character)
      index = value.index(after: index)
    }
    return result
  }

  private static func readsAsProse(_ value: String) -> Bool {
    let text = withoutInterpolations(value)
      .trimmingCharacters(in: CharacterSet(charactersIn: " ·—-|:"))
    guard text.count >= 6, text.split(separator: " ").count >= 2,
      text.first?.isLetter == true
    else { return false }
    let prose = text.filter { $0.isLetter || " ,.'’—-!?·".contains($0) }
    return Double(prose.count) / Double(text.count) >= 0.9
  }

  @Test("the scan reads something")
  func theScanIsNotVacuous() throws {
    let sources = try Self.appSources()
    #expect(sources.count > 10, "found \(sources.count) app sources — nothing would be checked")
    let all = sources.flatMap(\.lines)
    #expect(
      all.contains { Self.literals(in: $0).contains(where: Self.readsAsProse) },
      "the prose detector matched nothing at all — it would pass on anything")
  }

  @Test("every deliberate exception still exists")
  func theExceptionListDoesNotRot() throws {
    let all = try Self.appSources().flatMap(\.lines).joined()
    for value in Self.deliberateEnglish where !all.contains(value) {
      Issue.record("\(value) is allow-listed but no longer in the tree")
    }
    let names = Set(try Self.appSources().map(\.path))
    for file in Self.dataOnlyFiles where !names.contains(file) {
      Issue.record("\(file) is exempt but no longer in the tree")
    }
  }

  @Test("VoculaWhisper has no user-facing copy at all")
  func theUnscannedTargetSaysNothing() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Sources/VoculaWhisper")
    let files =
      FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
      .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
    #expect(files.count >= 3, "found \(files.count) files — the check would pass on nothing")
    for file in files {
      let source = try String(contentsOf: file, encoding: .utf8)
      let place = file.lastPathComponent
      if source.contains("String(localized:") || source.contains("LocalizedStringResource(") {
        Issue.record("\(place) looks up a key, so VoculaWhisper is no longer exempt")
      }
    }
  }

  @Test("no sentence bypasses the catalog")
  func noProseIsALiteral() throws {
    for file in try Self.appSources() {
      for (number, line) in file.lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("//"),
          !Self.dataOnlyFiles.contains(file.path),
          !Self.safeContext.contains(where: line.contains)
        else { continue }
        for value in Self.literals(in: line)
        where Self.readsAsProse(value) && !Self.deliberateEnglish.contains(value) {
          let place = "\(file.path):\(number + 1)"
          Issue.record("\(place) writes a sentence as a literal: \"\(value)\"")
        }
      }
    }
  }
}

@Suite("Every casing names the locale it cases in")
struct InvariantCasingTests {
  private static let layoutTruth = "KeyNames.swift"

  private static let bare = [
    "uppercased()", "lowercased()", "localizedCapitalized",
    "localizedUppercase", "localizedLowercase",
  ]

  private static func sources() throws -> [(path: String, lines: [String])] {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let files = ["App/Vocula", "Sources/VoculaKit", "Sources/VoculaWhisper"]
      .flatMap { relative in
        FileManager.default.enumerator(
          at: root.appendingPathComponent(relative),
          includingPropertiesForKeys: nil)?
          .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
      }
    return try files.map {
      (
        path: $0.lastPathComponent,
        lines: SourceScan.logicalLines(try String(contentsOf: $0, encoding: .utf8))
      )
    }
  }

  @Test("the scan reads something")
  func theScanIsNotVacuous() throws {
    let sources = try Self.sources()
    #expect(sources.count > 30, "found \(sources.count) sources — nothing would be checked")
    let cased = sources.flatMap(\.lines).filter { $0.contains("capitalized(with:") }
    #expect(!cased.isEmpty, "found no cased-with-a-locale call — the scan is looking at nothing")
  }

  @Test("the one documented exception still exists")
  func theExceptionStillExists() throws {
    let names = Set(try Self.sources().map(\.path))
    #expect(
      names.contains(Self.layoutTruth),
      "\(Self.layoutTruth) is the named exception but is no longer in the tree")
  }

  @Test("nothing cases with the device's locale by accident")
  func everyCasingIsExplicit() throws {
    for file in try Self.sources() where file.path != Self.layoutTruth {
      for (number, line) in file.lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("//"), Self.bare.contains(where: line.contains)
        else { continue }
        let place = "\(file.path):\(number + 1)"
        Issue.record("\(place) cases with the device's locale: \(trimmed)")
      }
    }
  }
}
