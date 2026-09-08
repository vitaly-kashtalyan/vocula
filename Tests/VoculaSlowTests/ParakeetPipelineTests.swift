import FluidAudio
import Foundation
import Testing
import VoculaKit
import VoculaParakeet

private let modelDirectory = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent(
    "Library/Application Support/app.vocula.mac/Models/parakeet-tdt-0.6b-v3")

private var modelIsAbsent: Bool {
  !FileManager.default.fileExists(atPath: modelDirectory.path)
}

private func fixture(_ name: String) throws -> [Float] {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/\(name).f32")
  let data = try Data(contentsOf: url)
  return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

@Suite(
  "Parakeet on the recorded fixtures",
  .disabled(if: modelIsAbsent, "Parakeet model not downloaded"))
struct ParakeetPipelineTests {
  @Test(
    "Each fixture comes back as the sentence that was spoken",
    arguments: [
      ("en-phrase", "en", "Hello, this is a test"),
      ("es-phrase", "es", "Hola, esto es una prueba"),
      ("pl-phrase", "pl", "Jestem szczęśliwy i zadowolony"),
      ("ru-phrase", "ru", "Я счастлив и доволен"),
      ("pl-cue", "pl", "Jestem szczęśliwy i zadowolony"),
    ])
  func transcribesAFixture(name: String, code: String, expected: String) async throws {
    let engine = ParakeetEngine(modelDirectory: modelDirectory)
    let result = try await engine.transcribe(
      try fixture(name), languages: .pinned(code), deadline: .seconds(60))
    #expect(result.text.hasPrefix(expected))
    #expect(result.language == code)
  }

  @Test("Auto-detect passes no hint and still transcribes")
  func autoDetectNeedsNoHint() async throws {
    let engine = ParakeetEngine(modelDirectory: modelDirectory)
    let result = try await engine.transcribe(
      try fixture("ru-phrase"),
      languages: LanguageSelection(codes: ["ru", "pl"], autoDetect: true),
      deadline: .seconds(60))
    #expect(result.text.hasPrefix("Я счастлив и доволен"))
    #expect(result.languageScores.isEmpty)
  }
}

@Suite("Parakeet without any weights on disk")
struct ParakeetWithoutModelTests {
  @Test("Every code this app offers for Parakeet is one FluidAudio knows")
  func theCodeListIsNotAHandWrittenGuess() {
    for code in EngineLanguages.parakeetCodes {
      #expect(
        Language(rawValue: code) != nil,
        "\(code) would silently fall back to auto-detect, defeating the pin")
    }
  }

  @Test("A directory with no bundles is refused before FluidAudio can reach the network")
  func anEmptyDirectoryIsRefusedLocally() async throws {
    let nowhere = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let engine = ParakeetEngine(modelDirectory: nowhere)
    await #expect(throws: TranscriptionError.modelNotLoaded) {
      try await engine.transcribe(
        [Float](repeating: 0.1, count: 16000),
        languages: .pinned("en"), deadline: .seconds(5))
    }
  }

  @Test("An empty recording is answered without touching the model at all")
  func emptyAudioNeedsNoModel() async throws {
    let nowhere = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let engine = ParakeetEngine(modelDirectory: nowhere)
    let result = try await engine.transcribe(
      [], languages: .pinned("pl"), deadline: .seconds(1))
    #expect(result.text.isEmpty)
  }
}
