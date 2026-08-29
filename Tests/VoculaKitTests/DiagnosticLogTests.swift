import Foundation
import Testing

@testable import VoculaKit

@Suite("Diagnostic log")
struct DiagnosticLogTests {
  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).log")
  }

  @Test("events are appended and read back newest first")
  func appendAndRead() {
    let url = temporaryFile()
    let log = DiagnosticLog(fileURL: url)
    log.record("session.start", "session=1")
    log.record("session.stop", "session=1 reason=releasedHold")
    let recent = log.recent(10)
    #expect(recent.count == 2)
    #expect(recent.first?.kind == "session.stop")
  }

  @Test(
    "transcript-shaped fields are dropped, whatever alphabet they use",
    arguments: [
      "text=hello",
      "text=passwordhunter2",
      "detail=Hola",
      "note=my secret",
      "reason=this is a whole sentence",
    ])
  func transcriptShapedFieldsAreDropped(field: String) {
    let redacted = DiagnosticLog.redact(field)
    #expect(redacted.contains("hello") == false)
    #expect(redacted.contains("passwordhunter2") == false)
    #expect(redacted.contains("Hola") == false)
    #expect(redacted.contains("secret") == false)
    #expect(redacted.contains("sentence") == false)
  }

  @Test("an unknown key is dropped even when its value looks harmless")
  func unknownKeysAreDropped() {
    #expect(
      DiagnosticLog.redact("phrase=abc") == "<dropped>",
      "an unknown key is caller-controlled text and must not echo itself")
  }

  @Test("a spaced value cannot leak its first identifier-shaped word")
  func spacedValueLeaksNothing() {
    #expect(DiagnosticLog.redact("reason=password hunter2") == "<dropped>")
  }

  @Test("the redacted form does not publish the length of what it dropped")
  func lengthIsNotLeaked() {
    let short = DiagnosticLog.redact("text=ab")
    let long = DiagnosticLog.redact("text=abcdefghijklmnop")
    #expect(short == long)
  }

  @Test("allow-listed fields survive with their values intact")
  func allowedFieldsSurvive() {
    let redacted = DiagnosticLog.redact("session=3 reason=passTimeout ms=31000")
    #expect(redacted == "session=3 reason=passTimeout ms=31000")
  }

  @Test("an allow-listed key with the wrong shape is still dropped")
  func shapeIsEnforced() {
    #expect(DiagnosticLog.redact("session=notanumber") == "session=<dropped>")
    #expect(DiagnosticLog.redact("secureInput=maybe") == "secureInput=<dropped>")
  }

  @Test("the log is capped so it cannot grow without bound")
  func logIsCapped() {
    let url = temporaryFile()
    let log = DiagnosticLog(fileURL: url, maximumEvents: 5)
    for index in 0..<20 { log.record("session.start", "session=\(index)") }
    #expect(log.recent(100).count == 5)
  }

  @Test("an arbitrary event name cannot become a transcript side channel")
  func eventKindIsAllowListed() {
    let log = DiagnosticLog(fileURL: temporaryFile())
    log.record("my dictated secret", "session=1")
    #expect(log.recent(1).first?.kind == "unknown")
  }

  @Test(
    "a key that is over-length or non-ASCII cannot smuggle text through the key position",
    arguments: [String(repeating: "k", count: 500) + "=1", "contraseñasecreta=1"])
  func unsafeKeysAreDropped(field: String) {
    #expect(DiagnosticLog.redact(field) == "<dropped>")
  }

  @Test(
    "the microphone authorisation case survives kind and value redaction",
    arguments: OnboardingStatus.allCases)
  func microphoneStateIsAllowListed(status: OnboardingStatus) {
    let log = DiagnosticLog(fileURL: temporaryFile())
    log.record("permission.microphone", "state=\(status.rawValue)")
    let event = log.recent(1).first
    #expect(event?.kind == "permission.microphone")
    #expect(event?.detail == "state=\(status.rawValue)")
  }

  @Test("a dropped over-cap clipboard is recorded under its own kind, with no detail")
  func clipboardNotRestoredIsAllowListedAndContentFree() {
    let log = DiagnosticLog(fileURL: temporaryFile())
    log.record("insert.clipboardNotRestored", "")
    let event = log.recent(1).first
    #expect(event?.kind == "insert.clipboardNotRestored")
    #expect(event?.detail == "")
  }

  @Test("the language cycle logs whether detection is on, and nothing else")
  func languageCycleFields() {
    #expect(DiagnosticLog.redact("auto=true") == "auto=true")
    #expect(DiagnosticLog.redact("code=ru") == "code=<dropped>")
  }

  @Test("record stores the caller's timestamp rather than taking its own")
  func recordUsesProvidedTimestamp() {
    let log = DiagnosticLog(fileURL: temporaryFile())
    let suppliedAt = Date(timeIntervalSince1970: 1_000)
    log.record("session.start", "session=1", at: suppliedAt)
    #expect(log.recent(1).first?.timestamp == suppliedAt)
  }
  @Test(
    "the kinds the app writes survive redaction",
    arguments: [
      "audio.input", "session.noSpeech", "tap.rearm",
      "app.launch", "insert.clipboardNotRestored",
      "permission.accessibility", "language.cycle",
    ])
  func writtenKindsAreAllowed(kind: String) {
    let log = DiagnosticLog(fileURL: temporaryFile())
    log.record(kind, "")
    #expect(log.recent(1).first?.kind == kind)
  }
}

@Suite("Diagnostic log: the microphone wait")
struct DiagnosticLogMicrophoneWaitTests {
  private func log() -> (DiagnosticLog, URL) {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("diag-\(UUID().uuidString).json")
    return (DiagnosticLog(fileURL: url), url)
  }

  @Test("audio.ready survives the allow-list with both its fields")
  func recorded() {
    let (log, url) = self.log()
    defer { try? FileManager.default.removeItem(at: url) }
    log.record("audio.ready", "session=7 ms=812")
    let event = log.recent(1).first
    #expect(event?.kind == "audio.ready")
    #expect(event?.detail == "session=7 ms=812")
  }

  @Test("anything but a duration is dropped from it")
  func onlyNumbers() {
    let (log, url) = self.log()
    defer { try? FileManager.default.removeItem(at: url) }
    log.record("audio.ready", "session=7 ms=AirPods")
    #expect(log.recent(1).first?.detail == "session=7 ms=<dropped>")
  }
}

@Suite("Diagnostic log: clearing")
struct DiagnosticLogClearingTests {
  @Test("clear empties the log and what is written after it survives")
  func clears() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("diag-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let log = DiagnosticLog(fileURL: url)
    log.record("session.start", "session=1")
    log.clear()
    #expect(log.recent(10).isEmpty)
    log.record("session.start", "session=2")
    #expect(log.recent(10).map(\.detail) == ["session=2"])
  }

  @Test("clearing a second instance does not clear the live one")
  func clearingTheWrongInstanceIsUndone() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("diag-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let live = DiagnosticLog(fileURL: url)
    live.record("session.start", "session=1")
    DiagnosticLog(fileURL: url).clear()
    live.record("session.stop", "session=1 reason=releasedHold")
    let reread = DiagnosticLog(fileURL: url).recent(10)
    #expect(reread.count == 2, "the live log wrote its whole memory back")
  }
}

@Suite("Keyboard anomaly lines")
struct KeyboardAnomalyLogTests {
  @Test(
    "a long hold and a rapid retap are logged in full",
    arguments: [
      ("gesture.longHold", "ms=41230 kbd=41"),
      ("gesture.rapidRetap", "ms=180 kbd=41"),
    ])
  func kindsAndFieldsSurvive(_ kind: String, _ detail: String) {
    #expect(
      DiagnosticLog.redact(detail) == detail,
      "a field was dropped from \(kind)")
  }

  @Test("a cancelled tap carries how long it was held")
  func cancelKeepsItsDuration() {
    #expect(
      DiagnosticLog.redact("session=3 reason=tooShort ms=41")
        == "session=3 reason=tooShort ms=41")
  }

  @Test("a non-numeric keyboard field is dropped")
  func kbdMustBeANumber() {
    #expect(DiagnosticLog.redact("kbd=Keychron-K2") == "kbd=<dropped>")
  }
}

@Suite("The allow-list and the code agree, in both directions")
struct EmittedKindsTests {
  private static let emitters = try! NSRegularExpression(
    pattern:
      ##"(?:diagnose\??\(|\blog\(|\.record\(|recordDiagnostic\(|Line\(\s*event:\s*)\s*"([a-z][A-Za-z]*\.[A-Za-z]+)""##
  )

  private static func sources() throws -> [(path: String, text: String)] {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let files = ["App/Vocula", "Sources/VoculaKit", "Sources/VoculaWhisper"]
      .flatMap { relative in
        FileManager.default.enumerator(
          at: root.appendingPathComponent(relative),
          includingPropertiesForKeys: nil)?
          .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
      }
    return try files.map {
      (path: $0.lastPathComponent, text: try String(contentsOf: $0, encoding: .utf8))
    }
  }

  private static func emittedKinds() throws -> Set<String> {
    var found: Set<String> = []
    for file in try sources() where file.path != "DiagnosticLog.swift" {
      let text = file.text
      let range = NSRange(text.startIndex..., in: text)
      for match in emitters.matches(in: text, range: range) {
        guard let captured = Range(match.range(at: 1), in: text) else { continue }
        found.insert(String(text[captured]))
      }
    }
    return found
  }

  @Test("the scan finds the emitters")
  func theScanIsNotVacuous() throws {
    let emitted = try Self.emittedKinds()
    #expect(
      emitted.count > 25, "found \(emitted.count) emitted kinds — the check would pass on nothing")
    for kind in [
      "app.launch", "session.noSpeech", "permission.microphone",
      "audio.deviceScan", "guard.deny",
    ] {
      #expect(emitted.contains(kind), "\(kind) is emitted but the scan did not see it")
    }
  }

  @Test("nothing is emitted that would be stored as `unknown`")
  func everyEmittedKindIsAllowed() throws {
    for kind in try Self.emittedKinds().sorted() where !DiagnosticLog.isKindAllowed(kind) {
      Issue.record("\(kind) is emitted but not allow-listed — it would be stored as `unknown`")
    }
  }

  @Test("nothing is allow-listed that nobody emits")
  func theAllowListHasNoDeadEntries() throws {
    let emitted = try Self.emittedKinds()
    for kind in DiagnosticLog.allowedKindsForTesting.sorted() where !emitted.contains(kind) {
      Issue.record("\(kind) is allow-listed but nothing emits it")
    }
  }
}

@Suite("Negative status codes")
struct NegativeCodeTests {
  @Test("a negative number survives", arguments: ["-10875", "-1", "0", "42"])
  func negativeNumbersPass(_ value: String) {
    #expect(DiagnosticLog.redact("ms=\(value)") == "ms=\(value)")
  }

  @Test("a minus on its own is still refused")
  func loneMinus() {
    #expect(DiagnosticLog.redact("ms=-") == "ms=<dropped>")
  }

  @Test("an engine failure's underlying domain and code survive redaction")
  func engineFailureCauseSurvives() {
    let detail =
      "session=1 reason=engineFailed error=VOC-ENG-01"
      + " domain=com.apple.coreaudio.avfaudio code=-10851"
    #expect(DiagnosticLog.redact(detail) == detail)
  }
}

@Suite("AUHAL capture diagnostics")
struct CaptureDiagnosticsTests {
  @Test("a refused unit keeps which step failed, its status, and the devices in play")
  func startFailureKeepsEverythingItNeeds() {
    let detail = "step=initialize code=-10868 wanted=78 rate=48000 default=91"
    #expect(DiagnosticLog.redact(detail) == detail)
    #expect(DiagnosticLog.isKindAllowed("audio.startFailed"))
  }

  @Test("an input that stopped delivering is recorded")
  func silentInputIsAllowListed() {
    #expect(DiagnosticLog.isKindAllowed("audio.inputWentSilent"))
  }

  @Test("a render failure keeps its status")
  func renderFailureKeepsItsCode() {
    #expect(DiagnosticLog.redact("code=-10874") == "code=-10874")
    #expect(DiagnosticLog.isKindAllowed("audio.renderFailed"))
  }

  @Test("a failover keeps the device it moved to and how many it has made")
  func failoverKeepsWhatItNeeds() {
    #expect(DiagnosticLog.redact("wanted=78 count=1") == "wanted=78 count=1")
    #expect(DiagnosticLog.isKindAllowed("audio.failover"))
  }

  @Test("a system device-list listener that would not install is recorded")
  func deviceListWatchFailureIsAllowListed() {
    #expect(DiagnosticLog.redact("code=-4") == "code=-4")
    #expect(DiagnosticLog.isKindAllowed("audio.deviceListWatchFailed"))
  }

  @Test(
    "the kinds this change retired are gone",
    arguments: [
      "audio.deviceChangeIgnored", "audio.deviceChangedDuringSession",
      "audio.engineRenewed", "audio.inputRepairing", "audio.inputRepaired",
    ])
  func retiredKindsAreRemoved(_ kind: String) {
    #expect(!DiagnosticLog.isKindAllowed(kind), "\(kind) is dead and must not linger")
  }
}
