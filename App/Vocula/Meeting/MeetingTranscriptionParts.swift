import AVFoundation
import AppKit
import Foundation
import VoculaKit
import VoculaParakeet
import VoculaWhisper

enum MeetingReadResult: Equatable, Sendable {
  case transcript(MeetingTranscript)
  case failed(step: String, code: Int)
  case unavailable
}

struct MeetingTranscriptionParts {
  typealias Publish = @Sendable (MeetingTranscription) async -> Void

  var makeTranscriber:
    @MainActor (
      _ log: DiagnosticLog?, _ state: MeetingDiarizerState, _ publish: @escaping Publish
    ) -> MeetingTranscriber?
  var listing: @Sendable (_ log: DiagnosticLog?) async -> MeetingListingOutcome
  var transcript: @Sendable (_ id: UUID) async -> MeetingReadResult
  var updateHeader:
    @Sendable (
      _ id: UUID, _ busy: Bool, _ change: @escaping @Sendable (inout MeetingHeader) -> Void
    )
      async -> MeetingActionResult
  var delete: @Sendable (_ id: UUID, _ busy: Bool) async -> MeetingActionResult
  var write: @Sendable (_ data: Data, _ url: URL) async -> MeetingActionResult
  var playable: @Sendable (_ id: UUID) async -> MeetingPlayable
  var saveRecording: @Sendable (_ id: UUID, _ url: URL) async -> MeetingActionResult
  var makePlayer: @MainActor (_ wav: Data) -> (any MeetingPlayer)?
  var paste: @MainActor (String) -> Void
  var fetchDiarizer:
    @MainActor (
      DiagnosticLog?, @escaping @MainActor (Int?) -> Void, @escaping @MainActor () async -> Void
    ) -> Void

  @MainActor static var live: MeetingTranscriptionParts {
    VoculaAppDelegate.isUITesting ? MeetingFixture().parts() : liveSystem
  }

  @MainActor private static var liveSystem: MeetingTranscriptionParts {
    MeetingTranscriptionParts(
      makeTranscriber: { liveTranscriber(log: $0, state: $1, publish: $2) },
      listing: { await liveListing(log: $0) },
      transcript: { await liveRead($0) },
      updateHeader: { await liveUpdateHeader($0, busy: $1, $2) },
      delete: { await liveDelete($0, busy: $1) },
      write: { await liveWrite($0, to: $1) },
      playable: { await livePlayable($0) },
      saveRecording: { await liveSaveRecording($0, to: $1) },
      makePlayer: { livePlayer($0) },
      paste: { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
      },
      fetchDiarizer: { fetcher.fetch(log: $0, progress: $1, onReady: $2) })
  }

  @MainActor private static let fetcher = MeetingDiarizerFetcher()

  static func discardDiarizer(from store: ModelStore, isSecondCopy: Bool) -> Bool {
    guard !isSecondCopy, AppCoordinator.removeInstalled(.speakerDiarizer, from: store) else {
      return false
    }
    return !FileManager.default.fileExists(atPath: store.url(for: .speakerDiarizer).path)
  }

  @MainActor static func liveTranscriber(
    log: DiagnosticLog?, state: MeetingDiarizerState, publish: @escaping Publish
  ) -> MeetingTranscriber? {
    guard let store = Meetings.makeStore() else { return nil }
    return MeetingTranscriber(
      MeetingTranscriber.Dependencies(
        store: store,
        cipher: { try await existingKey() },
        model: { await Task.detached(priority: .utility) { chosenModel() }.value },
        makeRecognizer: { try await recognizer(for: $0) },
        makeDetector: { WhisperVADDetector(modelPath: ModelStore.app().url(for: .speechDetector)) },
        diarization: MeetingDiarization(
          state: state,
          isInstalled: { ModelStore.app().isReady([.speakerDiarizer]) },
          load: {
            try await ParakeetMeetingDiarizer.load(
              modelDirectory: ModelStore.app().url(for: .speakerDiarizer))
          },
          discard: {
            let removed = await Task.detached(priority: .utility) {
              discardDiarizer(from: .app(), isSecondCopy: VoculaAppDelegate.isSecondCopy)
            }.value
            if removed { log?.record("model.discarded", "model=speakerDiarizer") }
          },
          wallClock: { Date() }),
        now: { Meetings.hostNanos() },
        sleep: { try await Task.sleep(for: $0) },
        publish: publish,
        log: log))
  }

  nonisolated static func liveListing(log: DiagnosticLog?) async -> MeetingListingOutcome {
    guard let store = Meetings.makeStore() else { return .meetings([]) }
    do {
      let found = try await store.listing(cipher: existingKey())
      await sweep(store.tombstones(), log: log)
      return .meetings(found)
    } catch {
      return .failed(error) { store.holdsMeetings() }
    }
  }

  private nonisolated static func sweep(_ tombstones: [URL], log: DiagnosticLog?) async {
    guard !tombstones.isEmpty else { return }
    await Task.detached(priority: .utility) {
      for tombstone in tombstones {
        do { try MeetingStore.removeTombstone(tombstone) } catch {
          guard case MeetingStoreError.failed(let step, let code) = error else { continue }
          log?.record("meeting.storeFailed", "action=delete step=\(step) code=\(code)")
        }
      }
    }.value
  }

  nonisolated static func liveUpdateHeader(
    _ id: UUID, busy: Bool, _ change: @escaping @Sendable (inout MeetingHeader) -> Void
  ) async -> MeetingActionResult {
    guard let store = Meetings.makeStore() else { return .refused }
    do {
      try await store.updateHeader(of: id, cipher: existingKey(), busy: busy, change)
      return .done
    } catch {
      return .from(error)
    }
  }

  nonisolated static func liveDelete(_ id: UUID, busy: Bool) async -> MeetingActionResult {
    guard let store = Meetings.makeStore() else { return .refused }
    do {
      try await store.delete(id, cipher: existingKey(), busy: busy)
      return .done
    } catch {
      return .from(error)
    }
  }

  nonisolated static func liveRead(_ id: UUID) async -> MeetingReadResult {
    guard let store = Meetings.makeStore() else { return .unavailable }
    do {
      return .transcript(try await store.transcript(of: id, cipher: existingKey()))
    } catch MeetingFailure.secondCopy {
      return .unavailable
    } catch {
      return switch MeetingActionResult.from(error) {
      case .failed(let step, let code): .failed(step: step, code: code)
      case .done, .refused: .failed(step: "read", code: 0)
      }
    }
  }

  nonisolated static func liveWrite(_ data: Data, to url: URL) async -> MeetingActionResult {
    await Task.detached(priority: .utility) {
      do {
        try data.write(to: url, options: .atomic)
        return .done
      } catch {
        return .failed(step: "write", code: (error as NSError).code)
      }
    }.value
  }

  nonisolated static func livePlayable(_ id: UUID) async -> MeetingPlayable {
    do {
      return .wav(MeetingRecording.wav(try await mixedRecording(id)))
    } catch {
      return switch MeetingActionResult.from(error) {
      case .failed(let step, let code): .failed(step: step, code: code)
      case .done, .refused: .failed(step: "read", code: 0)
      }
    }
  }

  nonisolated static func liveSaveRecording(_ id: UUID, to url: URL) async -> MeetingActionResult {
    let mic: [Int16]
    let system: [Int16]
    do {
      let (store, header, cipher) = try await recorded(id)
      mic = try await MeetingRecording.track(.mic, of: header, in: store, cipher: cipher)
      system = try await MeetingRecording.track(.system, of: header, in: store, cipher: cipher)
    } catch {
      return .from(error)
    }
    do {
      try MeetingAudioFile.writeLossless(mic: mic, system: system, to: url)
      return .done
    } catch {
      try? FileManager.default.removeItem(at: url)
      return .failed(step: "write", code: (error as NSError).code)
    }
  }

  @MainActor static func livePlayer(_ wav: Data) -> (any MeetingPlayer)? {
    guard let player = try? AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue),
      player.prepareToPlay()
    else { return nil }
    return player
  }

  private nonisolated static func mixedRecording(_ id: UUID) async throws -> [Int16] {
    let (store, header, cipher) = try await recorded(id)
    var mic = try await MeetingRecording.track(.mic, of: header, in: store, cipher: cipher)
    let system = try await MeetingRecording.track(.system, of: header, in: store, cipher: cipher)
    MeetingRecording.mix(system, into: &mic)
    return mic
  }

  private nonisolated static func recorded(_ id: UUID) async throws -> (
    MeetingStore, MeetingHeader, any HistoryCipher
  ) {
    guard let store = Meetings.makeStore() else { throw MeetingStoreError.refused }
    let cipher = try await existingKey()
    guard let header = await store.header(of: id, cipher: cipher) else {
      throw MeetingStoreError.failed(step: "open", code: 0)
    }
    return (store, header, cipher)
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

}
