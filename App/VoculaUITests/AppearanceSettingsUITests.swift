import XCTest

@MainActor
final class AppearanceSettingsUITests: XCTestCase {
  func testTheSectionOffersTheThreeAppearances() throws {
    let window = try openSection("appearance")

    for (id, title) in [
      ("system", "Match System"), ("light", "Light"),
      ("dark", "Dark"),
    ] {
      let tile = window.buttons["appearance.\(id)"]
      XCTAssertTrue(
        tile.waitForExistence(timeout: 5),
        "the Appearance section is missing “\(title)”")
      if ProcessInfo.processInfo.environment["VOCULA_UI_LANG"] == nil {
        XCTAssertEqual(
          tile.label, title,
          "the “\(id)” tile is not named “\(title)”")
      }
    }

    // Appearance shares the real container with the developer's own setting —
    // only the key bindings are diverted under -VoculaUITest — so a run that
    // clicked the tiles and walked away would leave their Mac repainted.
    // This test does NOT click the tiles. Appearance shares the real container
    // with the developer's own setting — only the key bindings are diverted
    // under -VoculaUITest — and it cannot be put back afterwards: a UI test runs
    // in its own container, so reading or writing the app's domain from here is
    // measured to do nothing. A green run used to repaint the developer's Mac.
  }
}
