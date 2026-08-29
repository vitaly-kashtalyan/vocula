import Foundation
import Testing

@Suite("The localization guard reports on what it read")
struct LocalizationGuardTests {
  private static var script: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("scripts/check-localization.sh")
  }

  private struct Run {
    let status: Int32
    let out: String
    let err: String
  }

  private func run(_ root: String) throws -> Run {
    let task = Process()
    task.executableURL = Self.script
    task.arguments = [root]
    let out = Pipe()
    let err = Pipe()
    task.standardOutput = out
    task.standardError = err
    try task.run()
    let o = out.fileHandleForReading.readDataToEndOfFile()
    let e = err.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return Run(
      status: task.terminationStatus,
      out: String(decoding: o, as: UTF8.self),
      err: String(decoding: e, as: UTF8.self))
  }

  private func fixture(_ catalog: [String: Any]?, shipping: [String] = ["en", "ru"]) throws
    -> String
  {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("locguard-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let catalog {
      let data = try JSONSerialization.data(withJSONObject: catalog)
      try data.write(to: dir.appendingPathComponent("Localizable.xcstrings"))
    }
    let localization = dir.appendingPathComponent("Localization")
    try FileManager.default.createDirectory(at: localization, withIntermediateDirectories: true)
    try shipping.joined(separator: "\n").write(
      to: localization.appendingPathComponent("shipping.txt"),
      atomically: true, encoding: .utf8)
    return dir.path
  }

  private func catalog(
    state: String = "translated",
    pluralState: String? = nil
  ) -> [String: Any] {
    var localization: [String: Any] = ["stringUnit": ["state": state, "value": "two"]]
    if let pluralState {
      localization = [
        "variations": [
          "plural": [
            "one": ["stringUnit": ["state": "translated", "value": "one"]],
            "many": ["stringUnit": ["state": pluralState, "value": "many"]],
          ]
        ]
      ]
    }
    return [
      "sourceLanguage": "en",
      "version": "1.0",
      "strings": [
        "some.key": [
          "comment": "a comment, so the comment check passes",
          "localizations": [
            "en": ["stringUnit": ["state": "translated", "value": "x"]],
            "ru": localization,
          ],
        ]
      ],
    ]
  }

  @Test("a catalog with no keys is reported as nothing checked")
  func emptyCatalogIsNotSuccess() throws {
    let root = try fixture(["sourceLanguage": "en", "version": "1.0", "strings": [:]])
    let result = try run(root)
    #expect(result.status != 0)
    #expect(result.err.contains("nothing was checked"))
  }

  @Test("an empty root is reported as nothing checked")
  func emptyRootIsNotSuccess() throws {
    let result = try run(try fixture(nil))
    #expect(result.status != 0)
    #expect(result.err.contains("nothing was checked"))
    #expect(
      result.out.contains("0 catalogs, 0 keys"),
      "the summary must show the emptiness even if the exit code is later broken")
  }

  @Test("the real tree passes, and says how much it read")
  func theRealTreePasses() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().path
    let result = try run(root)
    #expect(result.status == 0, "\(result.err)")
    #expect(result.out.range(of: #"localization: [1-9]"#, options: .regularExpression) != nil)
  }

  @Test("a needs_review state fails")
  func flatNeedsReviewFails() throws {
    let result = try run(try fixture(catalog(state: "needs_review")))
    #expect(result.status != 0)
    #expect(result.err.contains("needs_review"))
  }

  @Test("a needs_review state inside a plural variation fails too")
  func pluralNeedsReviewFails() throws {
    let result = try run(try fixture(catalog(pluralState: "needs_review")))
    #expect(result.status != 0)
    #expect(result.err.contains("needs_review"))
  }

  @Test("a key with no comment fails")
  func missingCommentFails() throws {
    var c = catalog()
    var strings = c["strings"] as! [String: Any]
    var entry = strings["some.key"] as! [String: Any]
    entry.removeValue(forKey: "comment")
    strings["some.key"] = entry
    c["strings"] = strings
    let result = try run(try fixture(c))
    #expect(result.status != 0)
    #expect(result.err.contains("has no comment"))
  }

  @Test("a draft locale is reported, not enforced")
  func draftLocaleDoesNotFail() throws {
    let root = try fixture(catalog(state: "needs_review"), shipping: ["en"])
    let result = try run(root)
    #expect(result.status == 0, "\(result.err)")
    #expect(result.out.contains("draft ru"))
    #expect(result.out.contains("ru (draft)"))
  }

  @Test("the same locale fails once it is shipping")
  func shippingLocaleFails() throws {
    let root = try fixture(catalog(state: "needs_review"), shipping: ["en", "ru"])
    let result = try run(root)
    #expect(result.status != 0)
    #expect(result.err.contains("needs_review"))
  }

  @Test("a translation that drops a format specifier fails")
  func droppedFormatSpecifierFails() throws {
    var c = catalog()
    var strings = c["strings"] as! [String: Any]
    var entry = strings["some.key"] as! [String: Any]
    var locales = entry["localizations"] as! [String: Any]
    locales["en"] = ["stringUnit": ["state": "translated", "value": "Hold %@ and speak"]]
    locales["ru"] = ["stringUnit": ["state": "translated", "value": "Говорите"]]
    entry["localizations"] = locales
    strings["some.key"] = entry
    c["strings"] = strings
    let result = try run(try fixture(c))
    #expect(result.status != 0)
    #expect(result.err.contains("format specifiers differ"))
  }

  @Test("more plural forms than the source is not a mismatch")
  func extraPluralFormsAreFine() throws {
    var c = catalog()
    var strings = c["strings"] as! [String: Any]
    var entry = strings["some.key"] as! [String: Any]
    entry["localizations"] = [
      "en": [
        "variations": [
          "plural": [
            "one": ["stringUnit": ["state": "translated", "value": "%lld thing"]],
            "other": ["stringUnit": ["state": "translated", "value": "%lld things"]],
          ]
        ]
      ],
      "ru": [
        "variations": [
          "plural": [
            "one": ["stringUnit": ["state": "translated", "value": "%lld вещь"]],
            "few": ["stringUnit": ["state": "translated", "value": "%lld вещи"]],
            "many": ["stringUnit": ["state": "translated", "value": "%lld вещей"]],
            "other": ["stringUnit": ["state": "translated", "value": "%lld вещи"]],
          ]
        ]
      ],
    ]
    strings["some.key"] = entry
    c["strings"] = strings
    let result = try run(try fixture(c))
    #expect(result.status == 0, "\(result.err)")
  }

  @Test("a plural form that omits the count is not a mismatch")
  func pluralFormMayOmitTheCount() throws {
    var c = catalog()
    var strings = c["strings"] as! [String: Any]
    var entry = strings["some.key"] as! [String: Any]
    entry["localizations"] = [
      "en": [
        "variations": [
          "plural": [
            "one": ["stringUnit": ["state": "translated", "value": "last day"]],
            "other": ["stringUnit": ["state": "translated", "value": "%lld days left"]],
          ]
        ]
      ],
      "ru": [
        "variations": [
          "plural": [
            "one": ["stringUnit": ["state": "translated", "value": "последний день"]],
            "other": ["stringUnit": ["state": "translated", "value": "осталось %lld дней"]],
          ]
        ]
      ],
    ]
    strings["some.key"] = entry
    c["strings"] = strings
    #expect(try run(try fixture(c)).status == 0)
  }

  @Test("a plural form that invents an argument fails")
  func pluralFormMayNotInventOne() throws {
    var c = catalog()
    var strings = c["strings"] as! [String: Any]
    var entry = strings["some.key"] as! [String: Any]
    entry["localizations"] = [
      "en": [
        "variations": [
          "plural": [
            "other": ["stringUnit": ["state": "translated", "value": "%lld days"]]
          ]
        ]
      ],
      "ru": [
        "variations": [
          "plural": [
            "other": ["stringUnit": ["state": "translated", "value": "%lld из %2$lld дней"]]
          ]
        ]
      ],
    ]
    strings["some.key"] = entry
    c["strings"] = strings
    let result = try run(try fixture(c))
    #expect(result.status != 0)
    #expect(result.err.contains("format specifiers differ"))
  }

  @Test("a shipping locale missing a key entirely fails")
  func shippingLocaleMissingAKeyFails() throws {
    var c = catalog()
    var strings = c["strings"] as! [String: Any]
    var entry = strings["some.key"] as! [String: Any]
    entry["localizations"] = ["en": ["stringUnit": ["state": "translated", "value": "x"]]]
    strings["some.key"] = entry
    c["strings"] = strings
    let result = try run(try fixture(c, shipping: ["en", "ru"]))
    #expect(result.status != 0)
    #expect(result.err.contains("no translation at all"))
  }

  @Test("a DRAFT locale missing a key does not fail")
  func draftLocaleMissingAKeyPasses() throws {
    var c = catalog()
    var strings = c["strings"] as! [String: Any]
    var entry = strings["some.key"] as! [String: Any]
    entry["localizations"] = ["en": ["stringUnit": ["state": "translated", "value": "x"]]]
    strings["some.key"] = entry
    c["strings"] = strings
    let result = try run(try fixture(c, shipping: ["en"]))
    #expect(result.status == 0, "\(result.err)")
  }
}
