import AppKit
import Foundation
import VoculaKit
import VoculaParakeet
import VoculaWhisper

struct MeetingTranscriptionParts {
  typealias Publish = @Sendable (MeetingTranscription?) async -> Void

  var makeHold: @MainActor () -> MeetingHoldGate
  var makeTranscriber:
    @MainActor (_ log: DiagnosticLog?, _ hold: MeetingHoldGate, _ publish: @escaping Publish) ->
      MeetingTranscriber?
  var listing: @Sendable (_ log: DiagnosticLog?) async -> [MeetingListing]?
  var transcript: @Sendable (_ id: UUID) async -> MeetingTranscript?
  var paste: @MainActor (String) -> Void

  @MainActor static var live: MeetingTranscriptionParts {
    MeetingTranscriptionParts(
      makeHold: { liveHold() },
      makeTranscriber: { liveTranscriber(log: $0, hold: $1, publish: $2) },
      listing: { await liveListing(log: $0) },
      transcript: { await liveTranscript($0) },
      paste: { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
      })
  }

  nonisolated static func liveHold() -> MeetingHoldGate {
    MeetingHoldGate(
      hold: DictationHold(
        passDeadline: { Timings.default.passDeadline(forAudio: $0) },
        refineWait: {
          let settings = AppSettings()
          return settings.refineEnabled ? .seconds(settings.refineMaximumWait) : nil
        }),
      now: { Meetings.hostNanos() }, sleep: { try await Task.sleep(for: $0) })
  }

  @MainActor static func liveTranscriber(
    log: DiagnosticLog?, hold: MeetingHoldGate, publish: @escaping Publish
  ) -> MeetingTranscriber? {
    guard let store = Meetings.makeStore() else { return nil }
    return MeetingTranscriber(
      MeetingTranscriber.Dependencies(
        store: store,
        cipher: { try await existingKey() },
        model: { await Task.detached(priority: .utility) { chosenModel() }.value },
        makeRecognizer: { try await recognizer(for: $0) },
        makeDetector: { WhisperVADDetector(modelPath: ModelStore.app().url(for: .speechDetector)) },
        hold: hold,
        now: { Meetings.hostNanos() },
        sleep: { try await Task.sleep(for: $0) },
        publish: publish,
        log: log))
  }

  nonisolated static func liveListing(log: DiagnosticLog?) async -> [MeetingListing]? {
    guard let store = Meetings.makeStore() else { return nil }
    do {
      return try await store.listing(cipher: existingKey())
    } catch {
      let (step, code) = failure(of: error)
      log?.record("meeting.transcribeFailed", "step=\(step) code=\(code)")
      return nil
    }
  }

  nonisolated static func liveTranscript(_ id: UUID) async -> MeetingTranscript? {
    guard let store = Meetings.makeStore(), let cipher = try? await existingKey() else {
      return nil
    }
    return try? await store.transcript(of: id, cipher: cipher)
  }

  nonisolated static func chosenModel() -> MeetingModel? {
    let settings = AppSettings()
    let store = ModelStore.app()
    guard store.isReady([.speechDetector]),
      let model = EngineFallback.running(
        selected: settings.transcriptionModel, languages: settings.languages.codes,
        isReady: { store.isReady([$0]) })
    else { return nil }
    return MeetingModel(model: model, languages: settings.languages)
  }

  nonisolated static func recognizer(for model: MeetingModel) async throws
    -> any MeetingRecognizing
  {
    let url = ModelStore.app().url(for: model.model)
    switch ModelManifest.descriptor(for: model.model).family {
    case .parakeet: return try await ParakeetMeetingRecognizer.load(modelDirectory: url)
    case .whisper, .refiner: return try await WhisperMeetingRecognizer.load(modelPath: url)
    }
  }

  private nonisolated static func existingKey() async throws -> any HistoryCipher {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        continuation.resume(with: Result { try MeetingKey.cipher(mayMint: false) })
      }
    }
  }

  private nonisolated static func failure(of error: any Error) -> (String, Int) {
    switch error {
    case MeetingFailure.failed(let step, let code): (step, Int(code))
    case MeetingStoreError.failed(let step, let code): (step, code)
    default: ("key", 0)
    }
  }
}
