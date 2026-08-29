import Testing

@testable import VoculaKit

@Suite("IndicatorAction")
struct IndicatorActionTests {
  @Test("finished is ignored, not displayed")
  func finishedIsIgnored() {
    let action = indicatorAction(for: .finished(session: 1, state: .sent, reason: nil))
    #expect(action == .ignore)
  }

  @Test("idle is displayed as the resting state, not hidden")
  func idleDisplaysResting() {
    #expect(indicatorAction(for: .idle) == .display(.idle))
  }

  @Test("raising is displayed")
  func raisingDisplays() {
    #expect(indicatorAction(for: .raising) == .display(.raising))
  }

  @Test("listening is displayed with its level intact")
  func listeningDisplaysWithLevel() {
    #expect(indicatorAction(for: .listening(level: 0.42)) == .display(.listening(level: 0.42)))
  }

  @Test("working is displayed")
  func workingDisplays() {
    #expect(indicatorAction(for: .working) == .display(.working))
  }

  @Test("refused is displayed with its reason intact")
  func refusedDisplaysWithReason() {
    #expect(
      indicatorAction(for: .refused("test", session: 1))
        == .display(.refused("test", session: 1)))
  }
}

@Suite("Note supersession")
struct SupersedesNoteTests {
  @Test("a fresh gesture supersedes a still-live note")
  func raisingSupersedesNote() {
    #expect(supersedesNote(.raising))
  }

  @Test("a refusal supersedes a note it would otherwise be hidden behind")
  func refusalSupersedesNote() {
    #expect(supersedesNote(.refused("test", session: 1)))
  }

  @Test("a live session's own phases leave a note alone")
  func phasesDoNotSupersedeNote() {
    #expect(!supersedesNote(.idle))
    #expect(!supersedesNote(.listening(level: 0.4)))
    #expect(!supersedesNote(.working))
  }

  @Test("finished does not supersede a note — it must not disturb what the panel is showing")
  func finishedDoesNotSupersedeNote() {
    #expect(!supersedesNote(.finished(session: 1, state: .sent, reason: nil)))
  }
}
