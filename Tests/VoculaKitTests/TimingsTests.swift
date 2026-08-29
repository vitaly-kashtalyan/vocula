import Testing

@testable import VoculaKit

@Suite("Timings")
struct TimingsTests {
  @Test("defaults match the spec's constants table")
  func defaults() {
    let t = Timings.default
    #expect(t.minRecording == .milliseconds(300))
    #expect(t.maxRecording == .seconds(180))
    #expect(t.whisperPass == .seconds(30))
    #expect(t.queueWait == .seconds(120))
    #expect(t.maxPending == 8)
    #expect(t.clipboardRestore == .seconds(1))
    #expect(t.roleQuery == .milliseconds(150))
  }
  @Test("the pass deadline grows with the recording instead of staying flat")
  func passDeadlineScalesWithAudio() {
    let t = Timings.default
    #expect(t.passDeadline(forAudio: .seconds(1)) == t.whisperPass)
    #expect(t.passDeadline(forAudio: .seconds(5)) == t.whisperPass)
    #expect(t.passDeadline(forAudio: .seconds(60)) > t.whisperPass)
    #expect(t.passDeadline(forAudio: t.maxRecording) >= t.maxRecording)
  }

}
