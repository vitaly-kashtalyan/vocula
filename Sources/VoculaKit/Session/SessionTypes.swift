import Foundation

public enum SessionState: String, Codable, Sendable, Equatable {
  case recorded, noSpeech, transcribing, transcribed, sent, rejected, failed

  public var title: LocalizedStringResource {
    switch self {
    case .recorded:
      return LocalizedStringResource(
        "session.state.recorded", defaultValue: "recorded", bundle: .atURL(Bundle.module.bundleURL),
        comment: "History row status: the audio was captured.")
    case .noSpeech:
      return LocalizedStringResource(
        "session.state.noSpeech", defaultValue: "no speech",
        bundle: .atURL(Bundle.module.bundleURL),
        comment: "History row status: nothing was said.")
    case .transcribing:
      return LocalizedStringResource(
        "session.state.transcribing",
        defaultValue: "transcribing", bundle: .atURL(Bundle.module.bundleURL),
        comment: "History row status: recognition is still running.")
    case .transcribed:
      return LocalizedStringResource(
        "session.state.transcribed",
        defaultValue: "not inserted", bundle: .atURL(Bundle.module.bundleURL),
        comment: "History row status: text exists but never reached the caret.")
    case .sent:
      return LocalizedStringResource(
        "session.state.sent", defaultValue: "inserted", bundle: .atURL(Bundle.module.bundleURL),
        comment: "History row status: the text was pasted.")
    case .rejected:
      return LocalizedStringResource(
        "session.state.rejected", defaultValue: "refused", bundle: .atURL(Bundle.module.bundleURL),
        comment: "History row status: the insert was refused by the target guard.")
    case .failed:
      return LocalizedStringResource(
        "session.state.failed", defaultValue: "failed", bundle: .atURL(Bundle.module.bundleURL),
        comment: "History row status: the dictation ended in an error.")
    }
  }
}

public enum SessionFailure: String, Codable, Sendable, Equatable, CaseIterable {
  case passTimeout
  case queueTimeout
  case engineFailed
  case emptyTranscript
  case insertionFailed
  case overflow
  case silentInput
}

public actor TranscriptionGate {
  private struct Waiter {
    let continuation: CheckedContinuation<Bool, Never>
    let timeout: Task<Void, Never>
  }
  private var busy = false
  private var order: [UUID] = []
  private var waiting: [UUID: Waiter] = [:]

  public init() {}

  public func acquire(timeout: Duration) async -> Bool {
    guard busy else {
      busy = true
      return true
    }
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard !Task.isCancelled else {
          continuation.resume(returning: false)
          return
        }
        let timeoutTask = Task {
          try? await Task.sleep(for: timeout)
          guard !Task.isCancelled else { return }
          self.expire(id)
        }
        order.append(id)
        waiting[id] = Waiter(continuation: continuation, timeout: timeoutTask)
      }
    } onCancel: {
      Task { await self.expire(id) }
    }
  }

  public func release() {
    while let id = order.first {
      order.removeFirst()
      guard let waiter = waiting.removeValue(forKey: id) else { continue }
      waiter.timeout.cancel()
      waiter.continuation.resume(returning: true)
      return
    }
    busy = false
  }

  private func expire(_ id: UUID) {
    guard let waiter = waiting.removeValue(forKey: id) else { return }
    waiter.timeout.cancel()
    waiter.continuation.resume(returning: false)
  }
}

public protocol SessionRecording: Sendable {
  func createDraft(
    session: Int, startedAt: Date, durationMilliseconds: Int,
    targetBundleID: String?, modelID: String?
  ) async -> UUID?
  func markTruncated(_ id: UUID) async
  func attachMetrics(_ id: UUID, _ metrics: SpeechMetrics) async
  func attachRawText(_ id: UUID, _ text: String, language: String) async
  func attachFinalText(_ id: UUID, _ text: String) async
  func setState(_ id: UUID, _ state: SessionState, reason: String?) async
}

public enum ControllerStatus: Equatable, Sendable {
  case idle
  case raising
  case listening(level: Float)
  case working
  case refused(String, session: Int)
  case finished(session: Int, state: SessionState, reason: String?)
}

public enum IndicatorAction: Equatable, Sendable {
  case ignore
  case display(ControllerStatus)
}

public func indicatorAction(for status: ControllerStatus) -> IndicatorAction {
  switch status {
  case .finished: return .ignore
  default: return .display(status)
  }
}

public func supersedesNote(_ status: ControllerStatus) -> Bool {
  switch status {
  case .raising, .refused: return true
  case .idle, .listening, .working, .finished: return false
  }
}

public struct RefusalDedup: Sendable, Equatable {
  private var lastRefusedSession: Int?

  public init() {}

  public mutating func noted(session: Int) {
    lastRefusedSession = session
  }

  public mutating func alreadyExplained(session: Int) -> Bool {
    guard lastRefusedSession == session else { return false }
    lastRefusedSession = nil
    return true
  }
}
