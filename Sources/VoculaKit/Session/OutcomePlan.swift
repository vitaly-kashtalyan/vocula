import Foundation

public struct OutcomePlan: Equatable, Sendable {
  public struct Line: Equatable, Sendable {
    public let event: String
    public let detail: String
  }

  public var recordsUsage = false
  public var forgetsHold = false
  public var line: Line?
  public var notice: String?

  public init() {}
}

public enum OutcomePolicy {
  public static func plan(
    session: Int,
    state: SessionState,
    reason: String?,
    heldFor: Duration,
    inputIsSilenced: @autoclosure () -> Bool,
    historyIsRecording: Bool,
    alreadyExplained: Bool
  ) -> OutcomePlan {
    var plan = OutcomePlan()
    switch state {
    case .sent:
      plan.recordsUsage = true
    case .noSpeech:
      plan.forgetsHold = true
      plan.line = OutcomePlan.Line(
        event: "session.noSpeech",
        detail: "session=\(session) error=\(ErrorCode.noSpeech)")
      guard NoSpeechNotice.worthTelling(heldFor: heldFor) else { break }
      plan.notice = RefusalCopy.noSpeechText
    case .rejected, .failed:
      let silenced = inputIsSilenced()
      let code = reason.flatMap {
        ErrorCode.code(forRawReason: $0, inputIsSilenced: silenced)
      }
      plan.line = OutcomePlan.Line(
        event: state == .rejected ? "guard.deny" : "session.failed",
        detail: "session=\(session) reason=\(reason ?? "unknown")"
          + (code.map { " error=\($0)" } ?? ""))
      guard !alreadyExplained else { break }
      plan.notice = RefusalCopy.text(
        forRawReason: reason,
        historyIsRecording: historyIsRecording,
        inputIsSilenced: silenced)
    case .recorded, .transcribing, .transcribed:
      break
    }
    return plan
  }
}
