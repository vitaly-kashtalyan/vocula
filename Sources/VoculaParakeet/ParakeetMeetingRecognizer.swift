import FluidAudio
import Foundation
import VoculaKit

public actor ParakeetMeetingRecognizer: MeetingRecognizing {
  private let queue = DispatchSerialQueue(label: "vocula.meeting.parakeet", qos: .utility)
  private var manager: AsrManager?
  private var decoderLayers = 2

  public nonisolated var unownedExecutor: UnownedSerialExecutor {
    queue.asUnownedSerialExecutor()
  }

  private init() {}

  public static func load(modelDirectory: URL) async throws -> ParakeetMeetingRecognizer {
    let recognizer = ParakeetMeetingRecognizer()
    try await recognizer.open(modelDirectory)
    return recognizer
  }

  public func recognize(_ samples: [Float], languages: LanguageSelection) async throws
    -> [TimedText]
  {
    try await recognizeWithText(samples, languages: languages).0
  }

  func recognizeWithText(_ samples: [Float], languages: LanguageSelection) async throws
    -> ([TimedText], String)
  {
    guard let manager else { throw TranscriptionError.modelNotLoaded }
    guard !samples.isEmpty else { return ([], "") }
    let hint = languages.autoDetect ? nil : Language(rawValue: languages.pinned)
    var state = try TdtDecoderState(decoderLayers: decoderLayers)
    let result = try await manager.transcribe(samples, decoderState: &state, language: hint)
    let words = buildWordTimings(from: result.tokenTimings ?? []).map {
      TimedText(start: $0.startTime, end: $0.endTime, text: $0.word)
    }
    return (words, result.text)
  }

  private func open(_ directory: URL) async throws {
    guard let models = try? AsrModels.loadLocal(from: directory, version: .ultra) else {
      throw TranscriptionError.modelNotLoaded
    }
    let created = AsrManager(config: .default)
    do {
      try await created.loadModels(models)
    } catch {
      throw TranscriptionError.engineFailed("AsrManager.loadModels: \(error)")
    }
    manager = created
    decoderLayers = models.version.decoderLayers
  }
}
