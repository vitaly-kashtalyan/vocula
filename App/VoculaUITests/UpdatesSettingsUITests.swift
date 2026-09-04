import XCTest

final class UpdatesSettingsUITests: XCTestCase {
  // A SwiftUI Text puts its content in the AX value, not the label.
  private func text(_ identifier: String, in window: XCUIElement) -> String {
    window.descendants(matching: .any)[identifier].value as? String ?? ""
  }

  func testAFoundUpdateReplacesTheLastCheckedRow() throws {
    let window = try openSection(
      "permissions", arguments: ["-VoculaPretendUpdate", "9.9.9"])
    let named = window.descendants(matching: .any)["updates.available"]

    XCTAssertTrue(
      named.waitForExistence(timeout: 5),
      "nothing on Permissions named the found update")
    XCTAssertTrue(
      text("updates.available", in: window).contains("9.9.9"),
      "the row did not name the version")
    XCTAssertTrue(
      window.descendants(matching: .any)["updates.install"].exists,
      "no Install button beside the found update")
    XCTAssertFalse(
      window.descendants(matching: .any)["updates.check"].exists,
      "the row it replaces was still on screen beside it")
  }

  func testNoFoundUpdateAnnouncesNothing() throws {
    let window = try openSection("permissions")
    let check = window.descendants(matching: .any)["updates.check"]

    // The control: without it, a screen that drew no update rows at all would
    // pass both assertions below.
    XCTAssertTrue(
      check.waitForExistence(timeout: 5),
      "the update rows were not on screen, so nothing below was tested")
    XCTAssertFalse(
      window.descendants(matching: .any)["updates.available"].exists,
      "an update was announced without one being found")
    XCTAssertFalse(
      window.descendants(matching: .any)["updates.install"].exists,
      "an Install button appeared without an update to install")
  }
}
