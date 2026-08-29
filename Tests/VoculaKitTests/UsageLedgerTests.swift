import Foundation
import Testing

@testable import VoculaKit

@Suite("A clock that ran ahead can be forgotten")
struct ClockOvershootTests {
  private func ledger(_ defaults: UserDefaults, now: Date) -> UsageLedger {
    UsageLedger(defaults: defaults, calendar: .current, clock: { now })
  }

  private func suite() -> UserDefaults {
    let name = "overshoot.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  @Test("an ordinary run offers nothing")
  func nothingToForget() {
    let defaults = suite()
    let now = Date(timeIntervalSince1970: 1_755_000_000)
    ledger(defaults, now: now).advance()
    #expect(ledger(defaults, now: now).clockOvershoot() == nil)
  }

  @Test("drift under a day offers nothing")
  func driftIsNotAnOvershoot() {
    let defaults = suite()
    let now = Date(timeIntervalSince1970: 1_755_000_000)
    ledger(defaults, now: now.addingTimeInterval(23 * 60 * 60)).advance()
    #expect(ledger(defaults, now: now).clockOvershoot() == nil)
  }

  @Test("a clock that ran a year ahead is reported and can be cleared")
  func aYearAheadIsOffered() {
    let defaults = suite()
    let now = Date(timeIntervalSince1970: 1_755_000_000)
    let wrong = now.addingTimeInterval(365 * 24 * 60 * 60)
    ledger(defaults, now: wrong).advance()

    let overshoot = ledger(defaults, now: now).clockOvershoot()
    #expect(overshoot == wrong)
    ledger(defaults, now: wrong).startTrialIfNeeded()
    defaults.set(now.timeIntervalSinceReferenceDate, forKey: UsageLedger.firstRunKey)
    if case .trial = ledger(defaults, now: now).entitlement(licensed: false) {
      Issue.record("the trial should be over while the wrong date stands")
    }
    ledger(defaults, now: now).forgetClockHistory()
    #expect(ledger(defaults, now: now).clockOvershoot() == nil)
    guard case .trial = ledger(defaults, now: now).entitlement(licensed: false) else {
      Issue.record("forgetting the wrong date did not give the trial back")
      return
    }
  }
}
