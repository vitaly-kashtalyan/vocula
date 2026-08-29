import Testing

@testable import VoculaKit

@Suite("Tap policy and re-arm")
struct EventTapReArmTests {
  @Test("absorbing classes need the active tap even at rest")
  func activeTapAtRestForAbsorbingClasses() {
    let combo = GestureConfig(
      primary: KeyBinding(
        klass: .comboWithKey, keyCode: 0x02,
        modifiers: [.leftControl]))
    #expect(TapPolicy.needsActiveTap(config: combo, isRecording: false) == true)
    #expect(TapPolicy.needsActiveTap(config: combo, isRecording: true) == true)
  }

  @Test("modifier classes need the active tap only while recording")
  func activeTapOnlyWhileRecordingForModifiers() {
    let fn = GestureConfig(primary: .fn)
    #expect(TapPolicy.needsActiveTap(config: fn, isRecording: false) == false)
    #expect(TapPolicy.needsActiveTap(config: fn, isRecording: true) == true)
  }

  @Test("Esc is absorbed only while a recording is live")
  func escapeAbsorbedOnlyWhileRecording() {
    let fn = GestureConfig(primary: .fn)
    #expect(TapPolicy.absorbedKeys(config: fn, isRecording: false).escape == false)
    #expect(TapPolicy.absorbedKeys(config: fn, isRecording: true).escape == true)
  }

  @Test("the binding itself is absorbed only in absorbing classes")
  func bindingAbsorption() {
    let fn = GestureConfig(primary: .fn)
    let combo = GestureConfig(
      primary: KeyBinding(
        klass: .comboWithKey, keyCode: 0x02,
        modifiers: [.leftControl]))
    #expect(TapPolicy.absorbedKeys(config: fn, isRecording: true).primaryBinding == false)
    #expect(TapPolicy.absorbedKeys(config: combo, isRecording: false).primaryBinding == true)
  }

  @Test("absorption is decided per binding, not OR-ed across both")
  func absorptionIsPerBinding() {
    let split = GestureConfig(
      primary: .fn,
      languageCycle: KeyBinding(
        klass: .comboWithKey, keyCode: 0x02,
        modifiers: [.leftControl, .leftOption]))
    let set = TapPolicy.absorbedKeys(config: split, isRecording: false)
    #expect(set.primaryBinding == false)
    #expect(set.languageCycle == true)
  }

  @Test("a language-cycle combo is absorbed and keeps the active tap up at rest")
  func languageCycleNeedsTheActiveTap() {
    let config = GestureConfig(primary: .fn, languageCycle: .languageCycle)
    #expect(TapPolicy.absorbedKeys(config: config, isRecording: false).languageCycle == true)
    #expect(TapPolicy.needsActiveTap(config: config, isRecording: false) == true)
  }

  @Test("without a language-cycle binding nothing extra is absorbed")
  func noLanguageCycleNothingAbsorbed() {
    let config = GestureConfig(primary: .fn, languageCycle: nil)
    #expect(TapPolicy.absorbedKeys(config: config, isRecording: false).languageCycle == false)
    #expect(TapPolicy.needsActiveTap(config: config, isRecording: false) == false)
  }

  @Test("a disabled tap is re-armed, and repeated disables are counted")
  func reArmAndCount() {
    var counter = ReArmCounter()
    #expect(counter.disabled(at: .seconds(0)) == .reArm(attempt: 1))
    #expect(counter.disabled(at: .seconds(1)) == .reArm(attempt: 2))
    #expect(counter.disabled(at: .seconds(2)) == .reArmAndWarn(attempt: 3))
  }

  @Test("disables spread far apart do not accumulate into a warning")
  func countersDecayOverTime() {
    var counter = ReArmCounter()
    #expect(counter.disabled(at: .seconds(0)) == .reArm(attempt: 1))
    #expect(counter.disabled(at: .seconds(400)) == .reArm(attempt: 1))
  }

  @Test("an event carrying our signature is dropped before the state machine")
  func ownSyntheticEventIsDropped() {
    #expect(SelfEventFilter.isOurs(userData: SyntheticEventSignature.value) == true)
    #expect(SelfEventFilter.isOurs(userData: 0) == false)
    #expect(SelfEventFilter.isOurs(userData: SyntheticEventSignature.value + 1) == false)
  }

  @Test("a claimed press still owns its release after the session has started")
  func claimSurvivesTheSessionBoundary() {
    var ledger = SwallowLedger()
    ledger.claimBindingDown(0x02)
    #expect(ledger.ownsBindingUp(0x02) == true)
    #expect(ledger.releaseBindingUp(0x02) == true)
    #expect(ledger.ownsBindingUp(0x02) == false)
  }

  @Test("a release we did not claim is not ours to swallow")
  func unclaimedReleaseIsNotOurs() {
    var ledger = SwallowLedger()
    #expect(ledger.ownsBindingUp(0x02) == false)
    #expect(ledger.releaseBindingUp(0x02) == false)
    ledger.claimBindingDown(0x02)
    #expect(ledger.releaseBindingUp(0x01) == false)
    #expect(ledger.ownsBindingUp(0x02) == true)
  }

  @Test("a swallowed Esc press hands its release the same verdict")
  func escapeReleaseIsPairedWithItsPress() {
    var ledger = SwallowLedger()
    ledger.noteEscapeDown(swallowed: true)
    #expect(ledger.consumeEscapeUp() == true)
    #expect(ledger.consumeEscapeUp() == false)
  }

  @Test("an Esc press we let through does not swallow its release")
  func unswallowedEscapePassesBothHalves() {
    var ledger = SwallowLedger()
    ledger.noteEscapeDown(swallowed: false)
    #expect(ledger.consumeEscapeUp() == false)
  }

  @Test("an Esc press we let through does not hold the active tap open")
  func anUnswallowedEscapeDoesNotAwaitRelease() {
    var ledger = SwallowLedger()
    ledger.noteEscapeDown(swallowed: false)
    #expect(ledger.awaitsRelease == false)
  }

  @Test("the ledger reports an outstanding release, and reset clears it")
  func awaitsReleaseDrivesTheActiveTap() {
    var ledger = SwallowLedger()
    #expect(ledger.awaitsRelease == false)
    ledger.claimBindingDown(0x69)
    #expect(ledger.awaitsRelease == true)
    _ = ledger.releaseBindingUp(0x69)
    #expect(ledger.awaitsRelease == false)

    ledger.noteEscapeDown(swallowed: true)
    #expect(ledger.awaitsRelease == true)
    ledger.reset()
    #expect(ledger.awaitsRelease == false)
    #expect(ledger.consumeEscapeUp() == false)
  }

  @Test("a claim outlives the session it opened, so an abandoned gesture still pairs")
  func claimOutlivesAnAbandonedSession() {
    var ledger = SwallowLedger()
    ledger.claimBindingDown(0x02)
    #expect(ledger.ownsBindingUp(0x02) == true)
    #expect(ledger.releaseBindingUp(0x02) == true)
  }

  @Test("two overlapping claims are each paired independently, released in claim order")
  func overlappingClaimsPairIndependentlyInClaimOrder() {
    var ledger = SwallowLedger()
    ledger.claimBindingDown(0x01)
    ledger.claimBindingDown(0x02)
    #expect(ledger.ownsBindingUp(0x01) == true)
    #expect(ledger.ownsBindingUp(0x02) == true)
    #expect(ledger.releaseBindingUp(0x01) == true)
    #expect(ledger.ownsBindingUp(0x01) == false)
    #expect(ledger.ownsBindingUp(0x02) == true)
    #expect(ledger.releaseBindingUp(0x02) == true)
    #expect(ledger.ownsBindingUp(0x02) == false)
  }

  @Test("two overlapping claims are each paired independently, released in reverse order")
  func overlappingClaimsPairIndependentlyInReverseOrder() {
    var ledger = SwallowLedger()
    ledger.claimBindingDown(0x01)
    ledger.claimBindingDown(0x02)
    #expect(ledger.releaseBindingUp(0x02) == true)
    #expect(ledger.ownsBindingUp(0x01) == true)
    #expect(ledger.releaseBindingUp(0x01) == true)
    #expect(ledger.ownsBindingUp(0x01) == false)
    #expect(ledger.ownsBindingUp(0x02) == false)
    #expect(ledger.awaitsRelease == false)
  }

  @Test("a release for a third, never-claimed key code is not swallowed by an overlap")
  func unclaimedThirdKeyAmongOverlappingClaimsIsNotOurs() {
    var ledger = SwallowLedger()
    ledger.claimBindingDown(0x01)
    ledger.claimBindingDown(0x02)
    #expect(ledger.releaseBindingUp(0x03) == false)
    #expect(ledger.ownsBindingUp(0x01) == true)
    #expect(ledger.ownsBindingUp(0x02) == true)
  }

  @Test("Escape swallowed during interception still pairs with its own release")
  func interceptionEscapeStillPairsItsRelease() {
    var ledger = SwallowLedger()
    ledger.noteEscapeDown(swallowed: true)
    #expect(ledger.awaitsRelease == true)
    #expect(ledger.consumeEscapeUp() == true)
    #expect(ledger.awaitsRelease == false)
  }

  @Test("a claimed Escape press survives repeat keyDowns, and its release is still swallowed")
  func claimedEscapeSurvivesRepeatKeyDowns() {
    var ledger = SwallowLedger()
    ledger.noteEscapeDown(swallowed: true)
    ledger.noteEscapeDown(swallowed: false)
    ledger.noteEscapeDown(swallowed: false)
    #expect(ledger.awaitsRelease == true)
    #expect(ledger.consumeEscapeUp() == true)
  }

  @Test("an unclaimed Escape release passes through even with no prior noteEscapeDown call")
  func unclaimedEscapeReleaseWithNoPriorClaimPassesThrough() {
    var ledger = SwallowLedger()
    #expect(ledger.awaitsRelease == false)
    #expect(ledger.consumeEscapeUp() == false)
    #expect(ledger.consumeEscapeUp() == false)
  }

  @Test("a live check's absorbing candidate claims its press and releases on its own keyUp")
  func liveCheckAbsorbingCandidatePairsPressAndRelease() {
    var ledger = SwallowLedger()
    ledger.claimBindingDown(0x02)
    #expect(ledger.awaitsRelease == true)
    #expect(ledger.ownsBindingUp(0x02) == true)
    #expect(ledger.releaseBindingUp(0x02) == true)
    #expect(ledger.awaitsRelease == false)
  }

  @Test("a claim left by a cancelled or timed-out live check is still clearable")
  func liveCheckAbandonedClaimIsStillClearable() {
    var ledger = SwallowLedger()
    ledger.claimBindingDown(0x02)
    #expect(ledger.awaitsRelease == true)
    #expect(ledger.releaseBindingUp(0x02) == true)
    #expect(ledger.awaitsRelease == false)
  }

  @Test("releasing an already-cleared live-check claim is a harmless no-op")
  func liveCheckSafetyNetReleaseIsIdempotent() {
    var ledger = SwallowLedger()
    ledger.claimBindingDown(0x02)
    #expect(ledger.releaseBindingUp(0x02) == true)
    #expect(ledger.releaseBindingUp(0x02) == false)
    #expect(ledger.awaitsRelease == false)
  }

  @Test("a live-check release does not clear a normal-path claim on the same key code")
  func liveCheckReleaseDoesNotClearNormalClaim() {
    var ledger = SwallowLedger()
    ledger.claimBindingDown(0x02)
    ledger.claimBindingDown(0x02, owner: .liveCheck)
    #expect(ledger.releaseBindingUp(0x02, owner: .liveCheck) == true)
    #expect(ledger.ownsBindingUp(0x02) == true)
    #expect(ledger.awaitsRelease == true)
    #expect(ledger.releaseBindingUp(0x02) == true)
    #expect(ledger.awaitsRelease == false)
  }

  @Test("a normal-path release does not clear a live-check claim on the same key code")
  func normalReleaseDoesNotClearLiveCheckClaim() {
    var ledger = SwallowLedger()
    ledger.claimBindingDown(0x02, owner: .liveCheck)
    ledger.claimBindingDown(0x02)
    #expect(ledger.releaseBindingUp(0x02) == true)
    #expect(ledger.ownsBindingUp(0x02, owner: .liveCheck) == true)
    #expect(ledger.awaitsRelease == true)
    #expect(ledger.releaseBindingUp(0x02, owner: .liveCheck) == true)
    #expect(ledger.awaitsRelease == false)
  }

  @Test("a live-check-only claim is invisible under the default (.normal) owner")
  func liveCheckOnlyClaimIsInvisibleUnderNormalOwner() {
    var ledger = SwallowLedger()
    ledger.claimBindingDown(0x02, owner: .liveCheck)
    #expect(ledger.ownsBindingUp(0x02) == false)
    #expect(ledger.ownsBindingUp(0x02, owner: .normal) == false)
    #expect(ledger.ownsBindingUp(0x02, owner: .liveCheck) == true)
    #expect(ledger.releaseBindingUp(0x02) == false)
    #expect(ledger.awaitsRelease == true)
    #expect(ledger.releaseBindingUp(0x02, owner: .liveCheck) == true)
    #expect(ledger.awaitsRelease == false)
  }
}
