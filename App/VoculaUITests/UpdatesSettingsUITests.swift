import XCTest

final class UpdatesSettingsUITests: XCTestCase {
  // On macOS a SwiftUI Text carries its content as the AX VALUE, and its label
  // is empty — matching on label finds the element and reads nothing from it.
  // The version and not the sentence, because this bundle runs in de, ru and pl
  // too and a number reads the same in all of them.
  private func named(_ version: String, in window: XCUIElement) -> XCUIElement {
    window.staticTexts
      .matching(NSPredicate(format: "value CONTAINS %@", version))
      .firstMatch
  }

  func testAFoundUpdateIsNamedOnTheScreen() throws {
    let window = try openSection(
      "permissions", arguments: ["-VoculaPretendUpdate", "9.9.9"])

    XCTAssertTrue(
      named("9.9.9", in: window).waitForExistence(timeout: 5),
      "nothing on Permissions named the found update")
    XCTAssertTrue(
      window.descendants(matching: .any)["updates.install"].exists,
      "no Install button beside the found update")
  }

  func testNoFoundUpdateAnnouncesNothing() throws {
    let window = try openSection("permissions")

    XCTAssertFalse(
      window.descendants(matching: .any)["updates.install"].exists,
      "an update was announced without one being found")
    XCTAssertFalse(
      named("9.9.9", in: window).exists,
      "the substituted version leaked into a run that did not ask for it")
  }
}
