import Foundation
import Testing
import VoculaKit

@testable import VoculaWhisper

private let realModel = FileManager.default
  .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("app.vocula.mac/Models/ggml-large-v3-turbo.bin")

private let fixtureDirectory = URL(fileURLWithPath: "Tests/VoculaSlowTests/Fixtures")
private let slavicFixturesReady = ["pl-phrase.f32", "ru-phrase.f32", "pl-cue.f32"]
  .allSatisfy {
    FileManager.default.fileExists(atPath: fixtureDirectory.appendingPathComponent($0).path)
  }

private func samples(of fixture: String) throws -> [Float] {
  let data = try Data(contentsOf: fixtureDirectory.appendingPathComponent(fixture))
  var result = [Float](repeating: 0, count: data.count / MemoryLayout<Float>.stride)
  result.withUnsafeMutableBytes { data.copyBytes(to: $0) }
  return result
}

@Suite(
  "Polish beside Russian",
  .enabled(
    if: FileManager.default.fileExists(atPath: realModel.path) && slavicFixturesReady))
struct PolishDetectionTests {
  private let three = LanguageSelection(codes: ["en", "ru", "pl"], autoDetect: true)

  private func report(_ fixture: String) async throws -> Transcription {
    let engine = WhisperEngine(modelPath: realModel)
    let result = try await engine.transcribe(
      try samples(of: fixture), languages: three, deadline: .seconds(60))
    let scores = result.languageScores
      .sorted { $0.value > $1.value }
      .map { "\($0.key)=\(String(format: "%.4f", $0.value))" }
      .joined(separator: " ")
    print("[\(fixture)] chose \(result.language) | \(scores) | \(result.text)")
    return result
  }

  @Test("Polish is not mistaken for Russian when all three are selected")
  func polishWins() async throws {
    #expect(try await report("pl-phrase.f32").language == "pl")
  }

  @Test("565 ms of the start cue at the head does not move a confident detection")
  func theCueDoesNotDecideTheLanguage() async throws {
    #expect(try await report("pl-cue.f32").language == "pl")
  }

  @Test("Russian is not mistaken for Polish when all three are selected")
  func russianWins() async throws {
    #expect(try await report("ru-phrase.f32").language == "ru")
  }
}
