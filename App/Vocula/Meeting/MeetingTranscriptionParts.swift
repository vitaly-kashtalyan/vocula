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
  var transcript: @Sendable (_ id: UUID, _ log: DiagnosticLog?) async -> MeetingTranscript?
  var paste: @MainActor (String) -> Void

  @MainActor static var live: MeetingTranscriptionParts {
    MeetingTranscriptionParts(
      makeHold: { liveHold() },
      makeTranscriber: { liveTranscriber(log: $0, hold: $1, publish: $2) },
      listing: { await liveListing(log: $0) },
      transcript: { await liveTranscript($0, log: $1) },
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
          return DictationHold.refineWait(
            enabled: settings.refineEnabled, maximumSeconds: settings.refineMaximumWait)
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
      record(error, otherwise: "list", in: log)
      return nil
    }
  }

  nonisolated static func liveTranscript(_ id: UUID, log: DiagnosticLog?) async
    -> MeetingTranscript?
  {
    guard let store = Meetings.makeStore() else { return nil }
    do {
      return try await store.transcript(of: id, cipher: existingKey())
    } catch {
      record(error, otherwise: "copy", in: log)
      return nil
    }
  }

  nonisolated static func chosenModel() -> MeetingModel? {
    let settings = AppSettings()
    let store = ModelStore.app()
    return MeetingModel.choose(
      selected: settings.transcriptionModel, languages: settings.languages,
      isReady: { store.isReady([$0]) })
  }

  nonisolated static func recognizer(for model: MeetingModel) async throws
    -> any MeetingRecognizing
  {
    let url = ModelStore.app().url(for: model.model)
    if model.family == .parakeet {
      return try await ParakeetMeetingRecognizer.load(modelDirectory: url)
    }
    return try await WhisperMeetingRecognizer.load(modelPath: url)
  }

  private nonisolated static func existingKey() async throws -> any HistoryCipher {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        continuation.resume(with: Result { try MeetingKey.cipher(mayMint: false) })
      }
    }
  }

  private nonisolated static func record(
    _ error: any Error, otherwise: String, in log: DiagnosticLog?
  ) {
    let step: String
    let code: Int
    switch error {
    case MeetingFailure.secondCopy: return
    case MeetingFailure.failed(let failed, let status): (step, code) = (failed, Int(status))
    case MeetingStoreError.failed(let failed, let status): (step, code) = (failed, status)
    default: (step, code) = (otherwise, 0)
    }
    log?.record("meeting.transcribeFailed", "step=\(step) code=\(code)")
  }
}
