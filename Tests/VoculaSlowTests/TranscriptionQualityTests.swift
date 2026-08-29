import Foundation
import Testing
import VoculaKit

@testable import VoculaWhisper

private let realModel = FileManager.default
  .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("app.vocula.mac/Models/ggml-large-v3-turbo.bin")

private let fixtureDirectory = URL(fileURLWithPath: "Tests/VoculaSlowTests/Fixtures")
private let qualityFixturesReady = ["es-phrase.f32", "en-phrase.f32"].allSatisfy {
  FileManager.default.fileExists(atPath: fixtureDirectory.appendingPathComponent($0).path)
}

private func samples(of fixture: String) throws -> [Float] {
  let url = fixtureDirectory.appendingPathComponent(fixture)
  let data = try Data(contentsOf: url)
  guard data.count.isMultiple(of: MemoryLayout<Float>.stride) else {
    throw CocoaError(.fileReadCorruptFile)
  }
  var result = [Float](
    repeating: 0,
    count: data.count / MemoryLayout<Float>.stride)
  result.withUnsafeMutableBytes { destination in
    data.copyBytes(to: destination)
  }
  return result
}

private let qualityPassDeadline: Duration = .seconds(60)

@Suite(
  "Transcription quality",
  .enabled(
    if: FileManager.default.fileExists(atPath: realModel.path)
      && qualityFixturesReady))
struct TranscriptionQualityTests {
  private let selected = LanguageSelection(codes: ["es", "en"], autoDetect: true)

  @Test("a Spanish phrase yields its key words")
  func spanish() async throws {
    let engine = WhisperEngine(modelPath: realModel)
    let result = try await engine.transcribe(
      try samples(of: "es-phrase.f32"),
      languages: selected, deadline: qualityPassDeadline)
    #expect(result.language == "es")
    #expect(result.text.lowercased().contains("hola"))
    let firstP = try #require(result.firstTokenProbability)
    #expect(firstP > 0 && firstP <= 1)
  }

  @Test("an English phrase yields its key words")
  func english() async throws {
    let engine = WhisperEngine(modelPath: realModel)
    let result = try await engine.transcribe(
      try samples(of: "en-phrase.f32"),
      languages: selected, deadline: qualityPassDeadline)
    #expect(result.language == "en")
    #expect(result.text.lowercased().contains("hello"))
  }
}
