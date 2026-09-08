import FluidAudio
import Foundation
import VoculaKit

public actor ParakeetEngine: Transcribing {
  private let modelDirectory: URL
  private var manager: AsrManager?
  private var decoderLayers = 2

  private static let warmUpDeadline: Duration = .seconds(120)

  public init(modelDirectory: URL) { self.modelDirectory = modelDirectory }

  public func warmUp() async {
    _ = try? await transcribe(
      [Float](repeating: 0, count: Int(AudioFormat.sampleRate)),
      languages: .pinned(LanguageSelection.fallbackCode),
      deadline: Self.warmUpDeadline)
  }

  public func transcribe(
    _ samples: [Float], languages: LanguageSelection, deadline: Duration
  ) async throws -> Transcription {
    guard !samples.isEmpty else {
      return Transcription(text: "", language: languages.codes[0])
    }
    let manager = try await load()
    let layers = decoderLayers
    let hint = languages.autoDetect ? nil : Language(rawValue: languages.pinned)

    let result = try await withThrowingTaskGroup(of: ASRResult?.self) { group in
      group.addTask {
        var state = try TdtDecoderState(decoderLayers: layers)
        return try await manager.transcribe(samples, decoderState: &state, language: hint)
      }
      group.addTask {
        try await Task.sleep(for: deadline)
        return nil
      }
      let first = try await group.next() ?? nil
      group.cancelAll()
      return first
    }

    guard let result else { throw TranscriptionError.timedOut }
    return Transcription(
      text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
      language: languages.pinned)
  }

  private func load() async throws -> AsrManager {
    if let manager { return manager }
    let models: AsrModels
    do {
      models = try await AsrModels.load(from: modelDirectory, version: .v3)
    } catch {
      throw TranscriptionError.modelNotLoaded
    }
    decoderLayers = models.version.decoderLayers
    let created = AsrManager(config: .default)
    do {
      try await created.loadModels(models)
    } catch {
      throw TranscriptionError.engineFailed("AsrManager.loadModels: \(error)")
    }
    manager = created
    return created
  }
}
