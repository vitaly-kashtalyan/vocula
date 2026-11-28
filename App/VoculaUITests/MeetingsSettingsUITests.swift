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

  func testTheMeetingSwitchesTurnAndTurnBack() throws {
    let window = try openSection("meetings")
    for identifier in ["meetings.offersOnCall", "meetings.showsTime"] {
      let toggle = element(identifier, in: window)
      XCTAssertTrue(toggle.waitForExistence(timeout: 10), "the switch \(identifier) is missing")
      let before = "\(toggle.value ?? "")"
      let changed = NSPredicate { element, _ in
        "\((element as? XCUIElement)?.value ?? "")" != before
      }
      let restored = NSPredicate { element, _ in
        "\((element as? XCUIElement)?.value ?? "")" == before
      }
      toggle.click()
      expectation(for: changed, evaluatedWith: toggle)
      waitForExpectations(timeout: 5)
      toggle.click()
      expectation(for: restored, evaluatedWith: toggle)
      waitForExpectations(timeout: 5)
    }
  }

  func testAPretendCallIsOfferedAndNotNowClosesTheOffer() throws {
    _ = try openSection("meetings", arguments: ["-VoculaPretendCall"])
    let app = XCUIApplication()
    let notNow = app.buttons["callOffer.notNow"]
    XCTAssertTrue(notNow.waitForExistence(timeout: 10), "no call offer appeared")
    XCTAssertTrue(app.buttons["callOffer.record"].exists, "the offer has no Record button")
    notNow.click()
    XCTAssertTrue(notNow.waitForNonExistence(timeout: 5), "Not Now left the offer up")
  }

  func testAPretendCallEndIsOfferedAndKeepRecordingClosesTheOffer() throws {
    _ = try openSection("meetings", arguments: ["-VoculaPretendCallEnd"])
    let app = XCUIApplication()
    let keep = app.buttons["callEndOffer.keep"]
    XCTAssertTrue(keep.waitForExistence(timeout: 10), "no offer to stop recording appeared")
    XCTAssertTrue(app.buttons["callEndOffer.stop"].exists, "the offer has no Stop Recording button")
    keep.click()
    XCTAssertTrue(keep.waitForNonExistence(timeout: 5), "Keep Recording left the offer up")
  }

  func testAPretendQuietIsOfferedAndKeepRecordingClosesTheOffer() throws {
    _ = try openSection("meetings", arguments: ["-VoculaPretendQuiet"])
    let app = XCUIApplication()
    let keep = app.buttons["quietOffer.keep"]
    XCTAssertTrue(keep.waitForExistence(timeout: 10), "no offer to stop a quiet meeting appeared")
    XCTAssertTrue(app.buttons["quietOffer.stop"].exists, "the offer has no Stop Recording button")
    keep.click()
    XCTAssertTrue(keep.waitForNonExistence(timeout: 5), "Keep Recording left the offer up")
  }

  func testARecordedMeetingShowsItsMarkAndOffersPlayAndSave() throws {
    let window = try openSection("meetings")
    XCTAssertTrue(
      element("meetings.hasRecording.2", in: window).waitForExistence(timeout: 10),
      "the named meeting shows no recording mark")
    XCTAssertTrue(
      element("meetings.hasRecording.1", in: window).exists,
      "the waiting meeting shows no recording mark")
    XCTAssertFalse(
      element("meetings.hasRecording.0", in: window).exists,
      "a meeting without audio shows a recording mark")
    let app = XCUIApplication()
    element("meetings.menu.2", in: window).click()
    for action in ["play", "saveRecording"] {
      let item = element("meetings.action.\(action)", in: window)
      XCTAssertTrue(item.waitForExistence(timeout: 5), "the \(action) item is missing")
      XCTAssertTrue(item.isEnabled, "the \(action) item is disabled")
    }
    app.typeKey(.escape, modifierFlags: [])
    element("meetings.menu.0", in: window).click()
    XCTAssertTrue(element("meetings.action.open", in: window).waitForExistence(timeout: 5))
    XCTAssertFalse(
      element("meetings.action.play", in: window).exists,
      "a meeting without audio offers Play Recording")
    XCTAssertFalse(
      element("meetings.action.saveRecording", in: window).exists,
      "a meeting without audio offers Save Recording")
    app.typeKey(.escape, modifierFlags: [])
  }

  func testPlayRecordingShowsThePlayerAndStopClosesIt() throws {
    let window = try openSection("meetings")
    choose("play", onRow: 2, in: window)
    let pause = element("meetings.player.pause", in: window)
    XCTAssertTrue(pause.waitForExistence(timeout: 10), "Play Recording showed no player")
    XCTAssertTrue(
      element("meetings.player.position", in: window).exists, "the player has no position")
    pause.click()
    element("meetings.player.stop", in: window).click()
    XCTAssertTrue(pause.waitForNonExistence(timeout: 5), "Stop left the player in the row")
  }

  func testSaveRecordingAsksWhereAndCancelWritesNothing() throws {
    let window = try openSection("meetings")
    choose("saveRecording", onRow: 2, in: window)
    let app = XCUIApplication()
    let panel = NSPredicate { _, _ in app.dialogs.firstMatch.exists || app.sheets.firstMatch.exists
    }
    expectation(for: panel, evaluatedWith: nil)
    waitForExpectations(timeout: 5)
    app.typeKey(.escape, modifierFlags: [])
    let closed = NSPredicate { _, _ in
      !app.dialogs.firstMatch.exists && !app.sheets.firstMatch.exists
    }
    expectation(for: closed, evaluatedWith: nil)
    waitForExpectations(timeout: 5)
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
