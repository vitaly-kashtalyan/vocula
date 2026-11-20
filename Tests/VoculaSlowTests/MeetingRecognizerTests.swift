import Foundation
import Testing
import VoculaKit

@testable import VoculaParakeet
@testable import VoculaWhisper

private let models = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Library/Application Support/app.vocula.mac/Models")
private let whisperModel = models.appendingPathComponent("ggml-large-v3-turbo.bin")
private let parakeetModel = models.appendingPathComponent("parakeet-ultra-95eaa59")

private func fixture(_ name: String) throws -> [Float] {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/\(name).f32")
  let data = try Data(contentsOf: url)
  return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

private func collapsed(_ text: String) -> String {
  text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

@Suite(
  "Meeting recognisers on the recorded fixtures",
  .enabled(if: FileManager.default.fileExists(atPath: whisperModel.path)))
struct MeetingRecognizerTests {
  @Test(arguments: [("ru-phrase", "ru"), ("en-phrase", "en")])
  func whisperWordsJoinToItsText(fixtureName: String, code: String) async throws {
    let audio = try fixture(fixtureName)
    let languages = LanguageSelection(codes: [code], autoDetect: false, pinned: code)
    let recognizer = try await WhisperMeetingRecognizer.load(modelPath: whisperModel)
    let words = try await recognizer.recognize(audio, languages: languages)
    let plain = try await recognizer.plainText(audio, languages: languages)
    #expect(words.count > 1)
    #expect(collapsed(words.map(\.text).joined(separator: " ")) == collapsed(plain))
    let clip = Double(audio.count) / 16_000
    #expect(zip(words, words.dropFirst()).allSatisfy { $0.start <= $1.start })
    #expect(words.allSatisfy { $0.start >= 0 && $0.end <= clip + 0.05 })
  }
}

@Suite(
  "Parakeet meeting recogniser on the recorded fixtures",
  .enabled(if: FileManager.default.fileExists(atPath: parakeetModel.path)))
struct ParakeetMeetingRecognizerTests {
  @Test(arguments: [("ru-phrase", "ru"), ("en-phrase", "en")])
  func parakeetWordsJoinToItsText(fixtureName: String, code: String) async throws {
    let audio = try fixture(fixtureName)
    let languages = LanguageSelection(codes: [code], autoDetect: true)
    let recognizer = try await ParakeetMeetingRecognizer.load(modelDirectory: parakeetModel)
    let (words, text) = try await recognizer.recognizeWithText(audio, languages: languages)
    #expect(words.count > 1)
    #expect(collapsed(words.map(\.text).joined(separator: " ")) == collapsed(text))
    #expect(zip(words, words.dropFirst()).allSatisfy { $0.start <= $1.start })
  }
}
