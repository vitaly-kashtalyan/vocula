import XCTest

@MainActor
final class SettingsWindowUITests: XCTestCase {
  private let sections = Sidebar.sections

  func testTheWindowOpensOnStatus() throws {
    let window = try launchAndOpenSettings()
    waitForDetail("status", of: window)
  }

  func testTheSidebarShowsEverySectionAndItsGroups() throws {
    let window = try launchAndOpenSettings()
    for section in sections {
      XCTAssertTrue(
        window.descendants(matching: .any)[Sidebar.row(section)].exists,
        "the sidebar is missing “\(Sidebar.row(section))”")
    }
    for group in Sidebar.groups {
      XCTAssertTrue(
        window.descendants(matching: .any)[Sidebar.group(group)].exists,
        "the sidebar is missing “\(Sidebar.group(group))”")
    }
  }

  func testEveryRowSelectsItsSection() throws {
    let window = try launchAndOpenSettings()
    for section in sections {
      XCTAssertTrue(clickRow(section, in: window), "no sidebar row for “\(section)”")
      waitForDetail(section, of: window)
    }
  }

  func testSelectionFollowsInBothDirections() throws {
    let window = try launchAndOpenSettings()
    for section in sections.reversed() {
      XCTAssertTrue(clickRow(section, in: window), "no sidebar row for “\(section)”")
      waitForDetail(section, of: window)
    }
  }

  func testTheWindowTitleFollowsTheSelection() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["VOCULA_UI_LANG"] == nil,
      "this pins English copy, so it says nothing under a language override")
    let window = try launchAndOpenSettings()
    waitForTitle("Status", of: window)
    XCTAssertTrue(clickRow("history", in: window))
    waitForTitle("History", of: window)
  }

  func testTheStatusItemOpensTheAppsOwnMenu() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["VOCULA_UI_LANG"] == nil,
      "the only handle on a MenuBarExtra item is its label, which an "
        + "override changes")
    let app = try launch()
    let statusBar = app.menuBars.element(boundBy: 1)
    XCTAssertEqual(statusBar.statusItems.count, 1, "the menu bar icon is missing")
    statusBar.statusItems.element(boundBy: 0).click()
    let found = app.menus.allElementsBoundByIndex.contains {
      $0.menuItems["Keyboard…"].exists
    }
    XCTAssertTrue(found, "the app's own menu was not found behind the status item")
    app.typeKey(.escape, modifierFlags: [])
  }

  func testTheWindowCanBeReopenedAfterClosing() throws {
    let app = try launch()
    let first = openSettings(in: app)
    waitForDetail("status", of: first)

    first.buttons[XCUIIdentifierCloseWindow].click()
    XCTAssertTrue(
      app.windows.firstMatch.waitForNonExistence(timeout: 10),
      "the settings window did not close")

    let second = openSettings(in: app)
    waitForDetail("status", of: second)
    XCTAssertTrue(
      app.menuBars.element(boundBy: 0).menuBarItems.count > 0,
      "the app did not return to .regular, so the window is unreachable")
  }
}
