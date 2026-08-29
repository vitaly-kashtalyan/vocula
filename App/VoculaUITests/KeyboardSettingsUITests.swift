import XCTest

@MainActor
final class KeyboardSettingsUITests: XCTestCase {
  private func keyboard() throws -> XCUIElement { try openSection("keyboard") }

  func testTheSectionListsBothAssignableKeys() throws {
    let window = try keyboard()
    for slot in ["record", "languageCycle"] {
      let row = window.descendants(matching: .any)["binding.\(slot).title"]
      XCTAssertTrue(
        row.waitForExistence(timeout: 10),
        "the “binding.\(slot).title” row is missing")
    }
    let record = window.descendants(matching: .any)["binding.record.value"]
    XCTAssertTrue(record.waitForExistence(timeout: 10))
    XCTAssertFalse(record.label.isEmpty)
    XCTAssertNotEqual(record.label, "not set", "the record key always holds one")
    let cycle = window.descendants(matching: .any)["binding.languageCycle.value"]
    XCTAssertFalse(cycle.label.isEmpty, "the language key always holds one")
  }

  func testEveryRowHasItsOwnChangeButton() throws {
    let window = try keyboard()
    for slot in ["record", "languageCycle"] {
      let button = window.buttons["binding.\(slot).change"]
      XCTAssertTrue(
        button.waitForExistence(timeout: 10),
        "no Change button for \(slot)")
      XCTAssertTrue(button.isEnabled)
    }
  }

  func testChangingAKeyPutsOnlyThatRowIntoCapture() throws {
    let window = try keyboard()
    let record = window.buttons["binding.record.change"]
    XCTAssertTrue(record.waitForExistence(timeout: 10))
    record.click()

    let capturing = window.descendants(matching: .any)["binding.capturing"]
    XCTAssertTrue(
      capturing.waitForExistence(timeout: 5),
      "the record row never entered capture")
    XCTAssertFalse(
      window.buttons["binding.languageCycle.change"].isEnabled,
      "a second row could be recorded at the same time")

    let released = expectation(
      for: NSPredicate(format: "exists == true"),
      evaluatedWith: record)
    XCTAssertEqual(
      XCTWaiter().wait(for: [released], timeout: 15), .completed,
      "the capture never ended on its own")
  }

  func testTheTestButtonIsOfferedForBothKeys() throws {
    let window = try keyboard()
    XCTAssertTrue(window.buttons["binding.record.check"].waitForExistence(timeout: 10))
    XCTAssertTrue(window.buttons["binding.languageCycle.check"].exists)
  }
}
