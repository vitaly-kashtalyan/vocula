import Foundation
import Testing

@Suite("Text(verbatim:) means data, and only data")
struct VerbatimUsageTests {
  private static let copyNamespaces = [
    "MenuCopy.", "CommonCopy.", "HistoryScreenCopy.", "LicenceScreenCopy.", "OnboardingScreenCopy.",
    "MicrophoneScreenCopy.", "LanguageScreenCopy.", "DiagnosticsScreenCopy.", "KeyboardScreenCopy.",
    "ModelScreenCopy.", "StatusScreenCopy.", "AppearanceScreenCopy.", "SidebarCopy.",
    "SettingsSection.",
  ]

  private static let verbatimLiterals = [
    #"Text(verbatim: "Vocula")"#,
    #"Text(verbatim: "+")"#,
  ]

  private static let localizedResources = [
    "Text(section.title)", "Text(preference.title)", "Text(slot.title)", "Text(text)",
    "Text(record.state.title)", "Text(state.text)", "Text(caption)",
    "Text(alert.actionTitle)", "Text(menu.iconState.spokenState)",
    ".accessibilityLabel(preference.title)",
  ]

  private static func appSources() throws -> [(path: String, source: String)] {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("App/Vocula")
    let files =
      FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
      .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
    return try files.map {
      (
        path: $0.lastPathComponent,
        source: try String(
          contentsOf: $0,
          encoding: .utf8)
      )
    }
  }

  @Test("the scan actually reads something")
  func theScanIsNotVacuous() throws {
    let sources = try Self.appSources()
    #expect(sources.count > 10, "found no app sources to scan — the check would pass on nothing")
    #expect(sources.contains { $0.source.contains("Text(verbatim:") })

    #expect(
      try Self.widgetOffenders(in: "Button(title) {}").count == 1,
      "the widget scan no longer reports a known bare-String widget")
    #expect(
      try Self.widgetOffenders(in: ".help(caption)").count == 1,
      "the modifier scan no longer reports a known bare-String modifier")
    #expect(
      try Self.localizingTextOffenders(in: "Text(subtitle)").count == 1,
      "the Text scan no longer reports a known localizing Text(String)")
    #expect(
      try Self.widgetOffenders(in: "Button(MenuCopy.quit) {}").isEmpty,
      "the widget scan reports copy that goes through a catalog namespace")
  }

  @Test("no literal hides behind verbatim:")
  func noLiteralIsVerbatim() throws {
    for file in try Self.appSources() {
      for (number, line) in file.source.split(separator: "\n", omittingEmptySubsequences: false)
        .enumerated()
      where line.contains("Text(verbatim: \"")
        && !line.contains("Text(verbatim: \"\")")
        && !Self.verbatimLiterals.contains(where: line.contains)
      {
        Issue.record("\(file.path):\(number + 1) hides a literal behind verbatim:")
      }
    }
  }

  @Test("every allow-listed expression still exists")
  func theAllowListDoesNotRot() throws {
    let all = try Self.appSources().map(\.source).joined()
    for entry in Self.localizedResources {
      #expect(all.contains(entry), "\(entry) is allow-listed but no longer in the tree")
    }
    for literal in Self.verbatimLiterals {
      #expect(all.contains(literal), "\(literal) is allow-listed but no longer in the tree")
    }
    for namespace in Self.copyNamespaces {
      #expect(
        all.contains(namespace),
        "\(namespace) is allow-listed but no longer in the tree")
    }
  }

  static func widgetOffenders(in source: String) throws -> [(line: Int, code: String)] {
    let widget = try NSRegularExpression(
      pattern:
        #"\b(Button|Toggle|Label|Menu|Section|LabeledContent|Link|TextField)\(\s*(?!")[a-zA-Z_][\w.]*\s*(?![:\w(])"#
    )
    let modifier = try NSRegularExpression(
      pattern:
        #"\.(help|accessibilityLabel|accessibilityValue|navigationTitle)\(\s*(?!")[a-zA-Z_][\w.]*\s*(?![:\w(])"#
    )
    var offenders: [(line: Int, code: String)] = []
    for (number, text) in SourceScan.logicalLines(source).enumerated() {
      guard !text.trimmingCharacters(in: .whitespaces).hasPrefix("//"),
        !Self.localizedResources.contains(where: text.contains),
        !Self.copyNamespaces.contains(where: text.contains)
      else { continue }
      let range = NSRange(text.startIndex..., in: text)
      guard
        widget.firstMatch(in: text, range: range) != nil
          || modifier.firstMatch(in: text, range: range) != nil
      else { continue }
      offenders.append((number + 1, text.trimmingCharacters(in: .whitespaces)))
    }
    return offenders
  }

  @Test("no widget takes a bare String for its title")
  func noWidgetTakesABareString() throws {
    for file in try Self.appSources() {
      for offender in try Self.widgetOffenders(in: file.source) {
        Issue.record(
          "\(file.path):\(offender.line) hands a bare String to a widget: \(offender.code)")
      }
    }
  }

  static func localizingTextOffenders(in source: String) throws -> [(line: Int, code: String)] {
    let pattern = try NSRegularExpression(pattern: #"Text\((?!verbatim:|")[a-zA-Z]"#)
    var offenders: [(line: Int, code: String)] = []
    for (number, text) in SourceScan.logicalLines(source).enumerated() {
      guard !Self.localizedResources.contains(where: text.contains),
        !Self.copyNamespaces.contains(where: text.contains)
      else { continue }
      guard
        pattern.firstMatch(
          in: text,
          range: NSRange(text.startIndex..., in: text)) != nil
      else { continue }
      offenders.append((number + 1, text.trimmingCharacters(in: .whitespaces)))
    }
    return offenders
  }

  @Test("a String reaching a label says it is data")
  func noBareStringIsLocalized() throws {
    for file in try Self.appSources() {
      for offender in try Self.localizingTextOffenders(in: file.source) {
        Issue.record(
          "\(file.path):\(offender.line) hands a String to the localizing Text overload: \(offender.code)"
        )
      }
    }
  }
}
