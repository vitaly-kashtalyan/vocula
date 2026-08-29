import Foundation
import Testing

@testable import VoculaKit

@Suite("What a finished session asks the app to do")
struct OutcomePlanTests {
  private func plan(
    _ state: SessionState,
    reason: String? = nil,
    heldFor: Duration = .seconds(2),
    silenced: Bool = false,
    historyIsRecording: Bool = true,
    alreadyExplained: Bool = false
  ) -> OutcomePlan {
    OutcomePolicy.plan(
      session: 7, state: state, reason: reason, heldFor: heldFor,
      inputIsSilenced: silenced,
      historyIsRecording: historyIsRecording,
      alreadyExplained: alreadyExplained)
  }

  @Test("a sent dictation counts against the day and says nothing")
  func sentCountsAndIsQuiet() {
    let plan = plan(.sent)
    #expect(plan.recordsUsage)
    #expect(plan.line == nil)
    #expect(plan.notice == nil)
  }

  @Test(
    "only a sent dictation counts",
    arguments: [SessionState.recorded, .noSpeech, .transcribing, .transcribed, .rejected, .failed])
  func nothingElseCounts(_ state: SessionState) {
    #expect(plan(state, reason: "engineFailed").recordsUsage == false)
  }

  @Test(
    "the states in flight ask for nothing",
    arguments: [SessionState.recorded, .transcribing, .transcribed])
  func inFlightStatesAreInert(_ state: SessionState) {
    #expect(plan(state) == OutcomePlan())
  }

  @Test("no speech is always logged, even when it stays quiet")
  func noSpeechIsAlwaysLogged() {
    let brief = plan(.noSpeech, heldFor: .milliseconds(1))
    #expect(brief.line?.event == "session.noSpeech")
    #expect(brief.notice == nil, "a flick of the key should not lecture anyone")
    #expect(brief.forgetsHold)

    let held = plan(.noSpeech, heldFor: NoSpeechNotice.worthTellingAfter)
    #expect(held.line?.event == "session.noSpeech")
    #expect(held.notice != nil, "someone who held the key and spoke gets told")
  }

  @Test("a refusal and a failure are different lines")
  func rejectedAndFailedAreDistinct() {
    #expect(plan(.rejected, reason: "targetRefused").line?.event == "guard.deny")
    #expect(plan(.failed, reason: "engineFailed").line?.event == "session.failed")
  }

  @Test("a missing reason still files a line")
  func anUnknownReasonIsStillLogged() {
    let line = plan(.failed, reason: nil).line
    #expect(line?.detail.contains("reason=unknown") == true)
  }

  @Test("the error code reaches the log and not the sentence")
  func theCodeIsForTheLogOnly() {
    let plan = plan(.failed, reason: SessionFailure.engineFailed.rawValue)
    let code = ErrorCode.code(for: SessionFailure.engineFailed)
    #expect(plan.line?.detail.contains("error=\(code)") == true)
    #expect(plan.notice?.contains(code) == false)
  }

  @Test("a suppressed duplicate is silent on screen and still logged")
  func dedupSilencesTheScreenOnly() {
    let plan = plan(.failed, reason: "engineFailed", alreadyExplained: true)
    #expect(plan.line != nil)
    #expect(plan.notice == nil)
  }

  @Test("a silenced input changes both the code and the sentence")
  func silencedInputIsItsOwnOutcome() {
    let raw = SessionFailure.silentInput.rawValue
    let quiet = plan(.failed, reason: raw, silenced: false)
    let muted = plan(.failed, reason: raw, silenced: true)
    #expect(quiet.line?.detail != muted.line?.detail)
    #expect(quiet.notice != muted.notice)
  }
}
