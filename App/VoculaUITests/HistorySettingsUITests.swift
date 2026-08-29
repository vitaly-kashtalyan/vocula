import XCTest

@MainActor
final class HistorySettingsUITests: XCTestCase {
  func testHistoryShowsADayPageOrAnHonestEmptyState() throws {
    let window = try openSection("history")
    let strip = window.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.day."))
    let empty = window.descendants(matching: .any)["history.empty"]
    XCTAssertTrue(
      strip.firstMatch.waitForExistence(timeout: 10) || empty.exists,
      "neither a day strip nor an empty state is on screen")

    guard strip.firstMatch.exists else {
      XCTAssertFalse(window.descendants(matching: .any)["history.deleteMenu"].exists)
      return
    }
    XCTAssertGreaterThan(strip.count, 0, "the strip has a chip per day that exists")
    let menu = window.descendants(matching: .any)["history.deleteMenu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 5), "the delete menu is missing")
    menu.click()
    let day = window.descendants(matching: .any)["history.deleteDay"]
    let all = window.descendants(matching: .any)["history.deleteAll"]
    XCTAssertTrue(day.waitForExistence(timeout: 5), "the delete-this-day item is missing")
    XCTAssertTrue(all.exists, "the delete-all item is missing")
    XCUIApplication().typeKey(.escape, modifierFlags: [])
  }
}
