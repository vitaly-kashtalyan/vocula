import Foundation
import Testing

@testable import VoculaKit

@Suite("Trial and daily limit", .serialized)
struct TrialTests {
  private final class Clock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
  }

  private func fresh(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Rome")!
    return c
  }

  private func day(_ n: Int, hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 8, day: n, hour: hour))!
  }

  @Test("the trial is seven days, counted in local days")
  func trialLength() {
    let start = day(1)
    for elapsed in 0..<7 {
      #expect(
        TrialPolicy.entitlement(
          licensed: false, firstRun: start,
          now: day(1 + elapsed), usedToday: 0,
          calendar: calendar)
          == .trial(daysLeft: 7 - elapsed))
    }
    #expect(
      TrialPolicy.entitlement(
        licensed: false, firstRun: start, now: day(8),
        usedToday: 0, calendar: calendar)
        == .limited(remainingToday: 10))
  }

  @Test("the last hour of the seventh day is still the trial")
  func lastHour() {
    #expect(
      TrialPolicy.entitlement(
        licensed: false, firstRun: day(1, hour: 1),
        now: day(7, hour: 23), usedToday: 0,
        calendar: calendar)
        == .trial(daysLeft: 1))
  }

  @Test("after the trial it is ten a day, and the tenth is the last")
  func dailyLimit() {
    func remaining(after used: Int) -> Entitlement {
      TrialPolicy.entitlement(
        licensed: false, firstRun: day(1), now: day(30),
        usedToday: used, calendar: calendar)
    }
    #expect(remaining(after: 0) == .limited(remainingToday: 10))
    #expect(remaining(after: 9) == .limited(remainingToday: 1))
    #expect(remaining(after: 9).allowsDictation)
    #expect(remaining(after: 10) == .limited(remainingToday: 0))
    #expect(!remaining(after: 10).allowsDictation)
    #expect(remaining(after: 99) == .limited(remainingToday: 0))
  }

  @Test("a licence beats everything, including an exhausted day")
  func licensed() {
    #expect(
      TrialPolicy.entitlement(
        licensed: true, firstRun: day(1), now: day(300),
        usedToday: 99, calendar: calendar) == .licensed)
  }

  @Test("only recorded dictations count, and they reset with the local day")
  func counting() {
    let defaults = fresh("trial.counting")
    let clock = Clock(day(30))
    let ledger = UsageLedger(defaults: defaults, calendar: calendar) { clock.now }
    #expect(ledger.usedToday() == 0)
    ledger.recordDictation()
    ledger.recordDictation()
    #expect(ledger.usedToday() == 2)
    clock.now = day(31)
    #expect(ledger.usedToday() == 0)
  }

  @Test("setting the clock back does not extend the trial")
  func clockRollback() {
    let defaults = fresh("trial.rollback")
    let clock = Clock(day(1))
    let ledger = UsageLedger(defaults: defaults, calendar: calendar) { clock.now }
    ledger.startTrialIfNeeded()

    clock.now = day(20)
    ledger.advance()
    #expect(ledger.entitlement(licensed: false) == .limited(remainingToday: 10))

    clock.now = day(2)
    #expect(ledger.now() == day(20), "the clock moved backwards and was believed")
    #expect(ledger.entitlement(licensed: false) == .limited(remainingToday: 10))

    clock.now = day(25)
    #expect(ledger.now() == day(25))
  }

  @Test("the day's count survives a clock rolled back")
  func rollbackKeepsTheCount() {
    let defaults = fresh("trial.rollbackCount")
    let clock = Clock(day(30))
    let ledger = UsageLedger(defaults: defaults, calendar: calendar) { clock.now }
    for _ in 0..<10 { ledger.recordDictation() }
    #expect(ledger.usedToday() == 10)
    clock.now = day(29)
    #expect(ledger.usedToday() == 10, "yesterday was claimed and the count came back")
  }

  @Test("reading the entitlement writes nothing")
  func readsDoNotWrite() {
    let defaults = fresh("trial.pureReads")
    let ledger = UsageLedger(defaults: defaults, calendar: calendar) { day(30) }
    ledger.startTrialIfNeeded()
    let before = defaults.dictionaryRepresentation()

    _ = ledger.now()
    _ = ledger.firstRun()
    _ = ledger.usedToday()
    _ = ledger.entitlement(licensed: false)

    let after = defaults.dictionaryRepresentation()
    for key in [
      UsageLedger.firstRunKey, UsageLedger.highWaterKey,
      UsageLedger.usageDayKey, UsageLedger.usageCountKey,
    ] {
      #expect(
        String(describing: before[key]) == String(describing: after[key]),
        "reading changed \(key)")
    }
  }

  @Test("the first run is stamped once and then kept")
  func firstRunIsStable() {
    let defaults = fresh("trial.firstRun")
    let clock = Clock(day(5))
    let ledger = UsageLedger(defaults: defaults, calendar: calendar) { clock.now }
    ledger.startTrialIfNeeded()
    #expect(ledger.firstRun() == day(5))
    clock.now = day(9)
    #expect(ledger.firstRun() == day(5))
    #expect(ledger.entitlement(licensed: false) == .trial(daysLeft: 3))
  }

  @Test("the day key is the Gregorian one whatever calendar the region uses")
  func dayKeyMatchesHistorysSpellingUnderAnyRegion() {
    let moment = day(18)
    for identifier in [Calendar.Identifier.buddhist, .japanese, .hebrew, .islamic] {
      var regional = Calendar(identifier: identifier)
      regional.timeZone = TimeZone(identifier: "Europe/Rome")!
      #expect(
        UsageLedger.dayKey(moment, calendar: regional)
          == DayFileHistoryStore.dayFormatter.string(from: moment),
        "\(identifier) spells today differently from history")
    }
  }
}
