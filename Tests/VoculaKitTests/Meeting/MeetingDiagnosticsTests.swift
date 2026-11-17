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
}
