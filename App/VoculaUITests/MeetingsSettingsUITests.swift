import XCTest

@MainActor
final class MeetingsSettingsUITests: XCTestCase {
  private func element(_ identifier: String, in window: XCUIElement) -> XCUIElement {
    window.descendants(matching: .any)[identifier]
  }

  private func choose(_ action: String, onRow position: Int, in window: XCUIElement) {
    let menu = element("meetings.menu.\(position)", in: window)
    XCTAssertTrue(menu.waitForExistence(timeout: 10), "row \(position) has no actions menu")
    menu.click()
    let item = element("meetings.action.\(action)", in: window)
    XCTAssertTrue(item.waitForExistence(timeout: 5), "the \(action) item is missing")
    item.click()
  }

  func testTheFixtureMeetingsAreListedWithAMenuEach() throws {
    let window = try openSection("meetings")
    for position in 0..<3 {
      XCTAssertTrue(
        element("meetings.menu.\(position)", in: window).waitForExistence(timeout: 10),
        "row \(position) is missing")
    }
    XCTAssertFalse(element("meetings.empty", in: window).exists)
  }

  func testOpenShowsTheTranscriptAndClosesWithEscape() throws {
    let window = try openSection("meetings")
    choose("open", onRow: 2, in: window)
    let text = element("meetings.sheet.text", in: window)
    XCTAssertTrue(text.waitForExistence(timeout: 5), "the transcript sheet did not open")
    XCTAssertTrue((text.value as? String)?.contains("The build is green.") == true)
    XCUIApplication().typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(
      element("meetings.sheet.close", in: window).waitForNonExistence(timeout: 5),
      "Escape did not close the sheet")
  }

  func testRenameShowsTheNewNameOnTheRowMenu() throws {
    let window = try openSection("meetings")
    choose("rename", onRow: 2, in: window)
    let field = window.sheets.firstMatch.textFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5), "the rename alert has no field")
    field.typeKey("a", modifierFlags: .command)
    field.typeText("Renamed\r")
    let menu = element("meetings.menu.2", in: window)
    let renamed = NSPredicate(format: "title CONTAINS %@", "Renamed")
    expectation(for: renamed, evaluatedWith: menu)
    waitForExpectations(timeout: 5)
  }

  func testAPinnedMeetingOffersNoDelete() throws {
    let window = try openSection("meetings")
    let menu = element("meetings.menu.0", in: window)
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    menu.click()
    let delete = element("meetings.action.delete", in: window)
    XCTAssertTrue(delete.waitForExistence(timeout: 5))
    XCTAssertFalse(delete.isEnabled, "a pinned meeting must not offer Delete")
    XCUIApplication().typeKey(.escape, modifierFlags: [])
  }

  func testDeleteAsksFirstAndRemovesTheMeeting() throws {
    let window = try openSection("meetings")
    choose("delete", onRow: 1, in: window)
    let dialog = window.sheets.firstMatch
    XCTAssertTrue(dialog.waitForExistence(timeout: 5), "Delete did not ask first")
    XCTAssertEqual(dialog.buttons.count, 2)
    dialog.buttons.element(boundBy: 1).click()
    XCTAssertTrue(
      element("meetings.menu.2", in: window).waitForNonExistence(timeout: 5),
      "the deleted fixture meeting is still listed")
  }
}
