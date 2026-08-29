import Foundation
import Testing
import VoculaKit

@testable import VoculaWhisper

private let modelDirectory = FileManager.default
  .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("app.vocula.mac/Models")
private let detectorModel = modelDirectory.appendingPathComponent("ggml-silero-v5.1.2.bin")
private let transcriptionModel =
  modelDirectory
  .appendingPathComponent("ggml-large-v3-turbo.bin")

@Suite(
  "Concurrent ggml",
  .enabled(
    if:
      FileManager.default.fileExists(atPath: detectorModel.path)
      && FileManager.default.fileExists(atPath: transcriptionModel.path)))
struct ConcurrentGGMLTests {
  private func samples(_ count: Int) -> [Float] {
    (0..<count).map { i in Float(sin(Double(i) * 0.05)) * 0.05 }
  }

  @Test("the detector and the engine may run at once")
  func detectorAndEngineConcurrently() async throws {
    let detector = WhisperVADDetector(modelPath: detectorModel)
    let engine = WhisperEngine(modelPath: transcriptionModel)
    let audio = samples(16_000 * 3)

    for round in 1...4 {
      async let markup: Void = {
        _ = try? await detector.markup(audio)
      }()
      async let transcript: Void = {
        _ = try? await engine.transcribe(
          audio, languages: .pinned("ru"),
          deadline: .seconds(30))
      }()
      _ = await (markup, transcript)
      print("round \(round) survived")
    }
  }
}

@Suite(
  "Concurrent ggml lifecycle",
  .enabled(
    if:
      FileManager.default.fileExists(atPath: detectorModel.path)
      && FileManager.default.fileExists(atPath: transcriptionModel.path)))
struct ConcurrentGGMLLifecycleTests {
  private func samples(_ count: Int) -> [Float] {
    (0..<count).map { i in Float(sin(Double(i) * 0.05)) * 0.05 }
  }

  @Test("a VAD load landing inside the engine's Metal warm-up")
  func vadLoadDuringWarmUp() async throws {
    let audio = samples(16_000 * 3)
    for delay in [0, 20, 60, 150, 400, 900] {
      let engine = WhisperEngine(modelPath: transcriptionModel)
      let detector = WhisperVADDetector(modelPath: detectorModel)
      async let warm: Void = engine.warmUp()
      async let markup: Void = {
        try? await Task.sleep(for: .milliseconds(delay))
        _ = try? await detector.markup(audio)
      }()
      _ = await (warm, markup)
      print("warm-up overlap at \(delay) ms survived")
    }
  }

  @Test("an old engine freeing while a new one initialises")
  func freeDuringInit() async throws {
    let audio = samples(16_000 * 3)
    for round in 1...3 {
      var old: WhisperEngine? = WhisperEngine(modelPath: transcriptionModel)
      var oldDetector: WhisperVADDetector? = WhisperVADDetector(modelPath: detectorModel)
      _ = try? await old?.transcribe(
        audio, languages: .pinned("ru"),
        deadline: .seconds(60))
      _ = try? await oldDetector?.markup(audio)

      let fresh = WhisperEngine(modelPath: transcriptionModel)
      let freshDetector = WhisperVADDetector(modelPath: detectorModel)
      async let raising: Void = {
        await fresh.warmUp()
        _ = try? await freshDetector.markup(audio)
      }()
      async let dropping: Void = {
        try? await Task.sleep(for: .milliseconds(round * 30))
        old = nil
        oldDetector = nil
      }()
      _ = await (raising, dropping)
      print("round \(round) survived")
    }
  }
}
