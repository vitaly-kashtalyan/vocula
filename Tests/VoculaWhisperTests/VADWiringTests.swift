import Foundation
import Testing
import VoculaKit

@testable import VoculaWhisper

private let vadModel = FileManager.default.urls(
  for: .applicationSupportDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("app.vocula.mac/Models/ggml-silero-v5.1.2.bin")

@Suite("VAD wiring", .enabled(if: FileManager.default.fileExists(atPath: vadModel.path)))
struct VADWiringTests {
  @Test("two seconds of digital silence produce no speech")
  func silenceHasNoSpeech() async throws {
    let detector = WhisperVADDetector(modelPath: vadModel)
    let markup = try await detector.markup([Float](repeating: 0, count: 32_000))
    #expect(markup.hasSpeech == false)
    #expect(markup.metrics.totalMilliseconds == 2_000)
  }
}
