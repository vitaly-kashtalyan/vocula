import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingDiagnosticsTests {
  @Test(arguments: MeetingEnd.allCases) func theStopLineSurvives(end: MeetingEnd) {
    let d =
      "reason=\(end.rawValue) micSeconds=1 micSoundSeconds=1 systemSeconds=1"
      + " systemSoundSeconds=0 runs=2 droppedSeconds=0"
    #expect(DiagnosticLog.redact(d) == d)
  }

  @Test func transcriptionKindsAndKeysAreAllowed() {
    let log = DiagnosticLog(
      fileURL: meetingTemporaryDirectory().appendingPathComponent("diagnostics.json"))
    let summary =
      "meetings=2 audioSeconds=3 pieces=2 utterances=2 echoDropped=0 skippedChunks=1"
      + " tookSeconds=4 model=largeV3Turbo"
    log.record("meeting.transcribed", summary)
    log.record("meeting.transcribeFailed", "step=recognize code=-7")
    #expect(log.recent(2).map(\.kind) == ["meeting.transcribeFailed", "meeting.transcribed"])
    #expect(log.recent(2).map(\.detail) == ["step=recognize code=-7", summary])
  }

  @Test func aCounterTakesNoText() {
    #expect(DiagnosticLog.redact("micSeconds=abc") == "micSeconds=<dropped>")
    #expect(DiagnosticLog.redact("droppedSeconds=1.5") == "droppedSeconds=<dropped>")
  }

  @Test(arguments: [
    "meeting.start", "meeting.stop", "meeting.writeFailed", "meeting.recovered",
    "meeting.tapFailed", "meeting.sleepAllowed", "meeting.powerFailed",
  ])
  func theRecorderKindsAreAllowed(kind: String) {
    let log = DiagnosticLog(
      fileURL: meetingTemporaryDirectory().appendingPathComponent("diagnostics.json"))
    log.record(kind, "")
    #expect(log.recent(1).first?.kind == kind)
  }

  @Test(arguments: MeetingWarning.allCases) func aWarningLineIsStoredUnderItsKind(
    warning: MeetingWarning
  ) {
    let log = DiagnosticLog(
      fileURL: meetingTemporaryDirectory().appendingPathComponent("diagnostics.json"))
    log.record("meeting.warning", "reason=\(warning.rawValue)")
    #expect(log.recent(1).first?.kind == "meeting.warning")
    #expect(log.recent(1).first?.detail == "reason=\(warning.rawValue)")
  }

  @Test(arguments: ["meeting.micLost", "meeting.micReopened", "meeting.systemZeros"])
  func theLivenessKindsAreAllowed(kind: String) {
    let log = DiagnosticLog(
      fileURL: meetingTemporaryDirectory().appendingPathComponent("diagnostics.json"))
    log.record(kind, "")
    #expect(log.recent(1).first?.kind == kind)
  }

  @Test func storeFailureKindAndActionAreKept() {
    let log = DiagnosticLog(
      fileURL: meetingTemporaryDirectory().appendingPathComponent("diagnostics.json"))
    log.record("meeting.storeFailed", "action=delete step=rename code=2")
    #expect(log.recent(1).map(\.kind) == ["meeting.storeFailed"])
    #expect(log.recent(1).map(\.detail) == ["action=delete step=rename code=2"])
  }
}
