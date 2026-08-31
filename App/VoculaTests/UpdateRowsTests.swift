import Foundation
import Testing

@testable import Vocula

@Suite("The update rows are present even when there is no updater")
struct UpdateRowsTests {
  @Test("a Mac that has never checked says so rather than showing an empty row")
  func neverChecked() {
    #expect(UpdateRows.lastCheck(nil, now: Date()) == .never)
  }

  @Test("a check that just happened reads as today, not as a date")
  func today() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(UpdateRows.lastCheck(now.addingTimeInterval(-60), now: now) == .today)
  }

  @Test("an older check keeps its date, so a six-week silence is visible")
  func older() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let old = now.addingTimeInterval(-42 * 24 * 60 * 60)
    #expect(UpdateRows.lastCheck(old, now: now) == .on(old))
  }
}
