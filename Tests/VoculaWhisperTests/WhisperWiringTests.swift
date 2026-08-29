import Foundation
import Testing
import VoculaKit

@testable import VoculaWhisper

private let stubModel = URL(
  fileURLWithPath:
    "/opt/homebrew/share/whisper-cpp/for-tests-ggml-tiny.bin")

@Suite("Whisper wiring", .enabled(if: FileManager.default.fileExists(atPath: stubModel.path)))
struct WhisperWiringTests {
  @Test("the model loads and a buffer is accepted in the right format")
  func loadsAndAcceptsBuffer() async throws {
    let engine = WhisperEngine(modelPath: stubModel)
    let result = try await engine.transcribe(
      [Float](repeating: 0, count: 16_000),
      languages: .pinned("ru"), deadline: .seconds(30))
    #expect(result.language == "ru")
  }

  @Test("an expired deadline aborts the pass rather than returning late")
  func deadlineAborts() async throws {
    let engine = WhisperEngine(modelPath: stubModel)
    await #expect(throws: TranscriptionError.timedOut) {
      _ = try await engine.transcribe(
        [Float](repeating: 0.1, count: 16_000 * 30),
        languages: .pinned("ru"), deadline: .milliseconds(1))
    }
  }
}

@Suite("Whisper serialisation")
struct WhisperSerialisationTests {
  @Test("the engine is an actor, which is what serialises the passes")
  func engineIsAnActor() {
    #expect(WhisperEngine.self is any Actor.Type)
  }

  @Test(
    "dropping the context lets the next pass reload rather than fail for ever",
    .enabled(if: FileManager.default.fileExists(atPath: stubModel.path)))
  func aDroppedContextReloads() async throws {
    let engine = WhisperEngine(modelPath: stubModel)
    _ = try await engine.transcribe(
      [Float](repeating: 0, count: 16_000),
      languages: .pinned("ru"), deadline: .seconds(30))
    #expect(await engine.isLoaded)

    await engine.dropContext()
    #expect(await engine.isLoaded == false)

    _ = try await engine.transcribe(
      [Float](repeating: 0, count: 16_000),
      languages: .pinned("ru"), deadline: .seconds(30))
    #expect(await engine.isLoaded)
  }

}
