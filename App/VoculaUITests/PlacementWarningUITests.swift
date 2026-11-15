import XCTest

final class PlacementWarningUITests: XCTestCase {
  // A SwiftUI Text puts its content in the AX value, not the label.
  private func text(_ identifier: String, in window: XCUIElement) -> String {
    window.descendants(matching: .any)[identifier].value as? String ?? ""
  }

  private func assertDrawn(_ placement: String, notDrawn other: String) throws {
    let window = try openSection(
      "permissions", arguments: ["-VoculaPretendPlacement", placement])
    let title = window.descendants(matching: .any)["placement.\(placement)"]

    XCTAssertTrue(
      title.waitForExistence(timeout: 5), "Permissions drew no \(placement) warning")
    let words = text("placement.\(placement)", in: window)
    XCTAssertFalse(words.isEmpty, "the \(placement) warning has no title")
    XCTAssertFalse(
      words.hasPrefix("onboarding."), "the \(placement) title is a raw key: \(words)")
    XCTAssertFalse(
      text("placement.footer", in: window).isEmpty, "the \(placement) warning has no footer")
    XCTAssertFalse(
      window.descendants(matching: .any)["placement.\(other)"].exists,
      "the \(other) warning was drawn for a \(placement) copy")
  }

  func testATranslocatedCopyIsWarned() throws {
    try assertDrawn("translocated", notDrawn: "readOnlyVolume")
  }

  func testADiskImageCopyIsWarned() throws {
    try assertDrawn("readOnlyVolume", notDrawn: "translocated")
  }

  func testAnInstalledCopyIsNotWarned() throws {
    let window = try openSection("permissions")
    let check = window.descendants(matching: .any)["updates.check"]

    // The control: without it, a screen that drew nothing at all would pass.
    XCTAssertTrue(
      check.waitForExistence(timeout: 5),
      "the update rows were not on screen, so nothing below was tested")
    for placement in ["translocated", "readOnlyVolume"] {
      XCTAssertFalse(
        window.descendants(matching: .any)["placement.\(placement)"].exists,
        "a \(placement) warning was drawn for a copy with no placement problem")
    }
    XCTAssertFalse(
      window.descendants(matching: .any)["placement.footer"].exists,
      "a placement footer was drawn for a copy with no placement problem")
  }
}
