import XCTest

extension XCTestCase {
  func launch(arguments: [String] = []) throws -> XCUIApplication {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["VOCULA_UI_TESTS"] == "1",
      "UI tests drive the real screen. Set VOCULA_UI_TESTS=1 to run them.")
    return launchUnchecked(arguments: arguments)
  }

  private func launchUnchecked(arguments: [String]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-VoculaUITest"] + arguments
    if let language = ProcessInfo.processInfo.environment["VOCULA_UI_LANG"] {
      app.launchArguments += ["-AppleLanguages", "(\(language))"]
    }
    app.launch()
    app.activate()
    return app
  }

  func openSettings(in app: XCUIApplication) -> XCUIElement {
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(
      app.windows.firstMatch.waitForExistence(timeout: 20),
      "the settings window never appeared")
    return app.windows.firstMatch
  }

  func launchAndOpenSettings(arguments: [String] = []) throws -> XCUIElement {
    openSettings(in: try launch(arguments: arguments))
  }

  @discardableResult
  func clickRow(_ section: String, in window: XCUIElement) -> Bool {
    let row = window.descendants(matching: .any)[Sidebar.row(section)]
    guard row.waitForExistence(timeout: 5) else { return false }
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    return true
  }

  func waitForDetail(
    _ section: String, of window: XCUIElement,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let pane = window.descendants(matching: .any)[Sidebar.detail(section)]
    XCTAssertTrue(
      pane.waitForExistence(timeout: 5),
      "the detail pane never became “\(section)”", file: file, line: line)
  }

  func waitForTitle(
    _ title: String, of window: XCUIElement,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let matched = expectation(
      for: NSPredicate(format: "title == %@", title),
      evaluatedWith: window)
    let result = XCTWaiter().wait(for: [matched], timeout: 5)
    XCTAssertEqual(
      result, .completed,
      "the detail pane stayed on “\(window.title)” instead of “\(title)”",
      file: file, line: line)
  }
}

enum Sidebar {
  static let sections = [
    "status", "permissions",
    "keyboard", "languages", "microphone", "models",
    "history", "diagnostics",
    "licence", "appearance",
  ]
  static let groups = ["dictation", "data", "app"]

  static func row(_ section: String) -> String { "sidebar.\(section)" }
  static func group(_ name: String) -> String { "sidebar.group.\(name)" }
  static func detail(_ section: String) -> String { "detail.\(section)" }
}

extension XCTestCase {
  func openSection(_ section: String, arguments: [String] = []) throws -> XCUIElement {
    let window = try launchAndOpenSettings(arguments: arguments)
    XCTAssertTrue(
      clickRow(section, in: window),
      "no sidebar row identified “\(Sidebar.row(section))”")
    waitForDetail(section, of: window)
    return window
  }
}
