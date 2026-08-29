import Foundation
import Testing

@testable import VoculaKit

@Suite("Accessibility subrole mapping")
struct TargetProbeTimeoutTests {
  @Test("no answer — including a messaging timeout — maps to .unknown, not a block")
  func noAnswerYieldsUnknown() {
    #expect(
      SubroleAnswer.from(
        subrole: nil,
        secureSubroleIdentifier: "AXSecureTextField") == .unknown)
    #expect(TargetGuardPolicy.mayStart(focusedSubrole: .unknown))
  }

  @Test("the one positive sign of danger is recognised")
  func secureFieldRecognised() {
    #expect(
      SubroleAnswer.from(
        subrole: "AXSecureTextField",
        secureSubroleIdentifier: "AXSecureTextField")
        == .secureTextField)
  }

  @Test("any other subrole passes through unchanged")
  func otherSubrolePassesThrough() {
    #expect(
      SubroleAnswer.from(
        subrole: "AXTextArea",
        secureSubroleIdentifier: "AXSecureTextField")
        == .other("AXTextArea"))
  }
}

@Suite("Query budget arithmetic")
struct QueryBudgetTests {
  @Test("time remaining returns the seconds left until the deadline")
  func timeRemaining() {
    let base = ContinuousClock.now
    let deadline = base + .milliseconds(500)
    #expect(QueryBudget.secondsRemaining(until: deadline, now: base) == 0.5)
  }

  @Test("time exactly at the deadline yields no budget")
  func timeExactlyExpired() {
    let base = ContinuousClock.now
    let deadline = base + .milliseconds(200)
    #expect(QueryBudget.secondsRemaining(until: deadline, now: deadline) == nil)
  }

  @Test("time already past the deadline yields no budget")
  func timeAlreadyPast() {
    let base = ContinuousClock.now
    let deadline = base + .milliseconds(200)
    let now = deadline + .milliseconds(10)
    #expect(QueryBudget.secondsRemaining(until: deadline, now: now) == nil)
  }

  @Test("a deadline far in the future returns a large budget, unclamped")
  func deadlineFarInFuture() {
    let base = ContinuousClock.now
    let deadline = base + .seconds(9999)
    #expect(QueryBudget.secondsRemaining(until: deadline, now: base) == 9999)
  }
}

@Suite("Identity comparison — never-knew vs. lost-it asymmetry")
struct IdentityComparisonTests {
  @Test("no pin and no live read: reported unchanged")
  func neitherPresent() {
    #expect(
      IdentityComparison.same(pinned: Int?.none, now: Int?.none, isEqual: { $0 == $1 }) == true)
  }

  @Test("no pin but a live read exists: reported unchanged")
  func pinnedAbsentLivePresent() {
    #expect(IdentityComparison.same(pinned: Int?.none, now: 1, isEqual: { $0 == $1 }) == true)
  }

  @Test("a pin existed but the live read failed: reported changed")
  func pinnedPresentLiveAbsent() {
    #expect(IdentityComparison.same(pinned: 1, now: Int?.none, isEqual: { $0 == $1 }) == false)
  }

  @Test("both present and equal: reported unchanged")
  func bothPresentEqual() {
    #expect(IdentityComparison.same(pinned: 1, now: 1, isEqual: { $0 == $1 }) == true)
  }

  @Test("both present and different: reported changed")
  func bothPresentDifferent() {
    #expect(IdentityComparison.same(pinned: 1, now: 2, isEqual: { $0 == $1 }) == false)
  }
}
