import Foundation

public enum RefusalCopy {
  public static let hallucination = "hallucination"

  private static func recoveryKey(historyIsRecording: Bool) -> String {
    historyIsRecording ? "refusal.recovery.historyOn" : "refusal.recovery.historyOff"
  }

  public static let noSpeechKey = "refusal.noSpeech"

  public static var noSpeechText: String { text(forKey: noSpeechKey) }

  public static var engineFailedText: String { text(forKey: "refusal.engineFailed") }

  public static var overflowText: String { text(forKey: "refusal.overflow") }

  public static func text(forKey key: String) -> String {
    switch key {
    case "refusal.nothingInserted":
      return String(
        localized: "refusal.nothingInserted", defaultValue: "Nothing was inserted.",
        bundle: .module,
        comment: "Shown when a history record carries no reason at all.")
    case "refusal.recovery.historyOn":
      return String(
        localized: "refusal.recovery.historyOn",
        defaultValue: "The text is in History, or use Copy the last transcript.", bundle: .module,
        comment:
          "Where the text still is after a refusal. History and Copy the last transcript are this app's own names — use the sidebar's and the menu's words."
      )
    case "refusal.recovery.historyOff":
      return String(
        localized: "refusal.recovery.historyOff",
        defaultValue:
          "Use Copy the last transcript — history recording is off, so it is not saved.",
        bundle: .module,
        comment:
          "As refusal.recovery.historyOn but with history off. MUST NOT mention History: with recording off the text is not there, and saying so is a privacy statement."
      )
    case "refusal.noSpeech":
      return String(
        localized: "refusal.noSpeech",
        defaultValue: "No speech was found, so nothing was inserted. You can try again.",
        bundle: .module,
        comment:
          "Announced when a recording held no speech. Neither a rejection nor a failure — the user did speak, from their side, so it must not blame them or the microphone."
      )
    case "refusal.passTimeout":
      return String(
        localized: "refusal.passTimeout",
        defaultValue: "Transcription did not finish in time and was aborted. No text was produced.",
        bundle: .module,
        comment: "The whisper pass ran past its deadline.")
    case "refusal.queueTimeout":
      return String(
        localized: "refusal.queueTimeout",
        defaultValue:
          "The dictation waited too long for its turn and was dropped before transcription, so no text was produced.",
        bundle: .module,
        comment:
          "Dropped before transcription began. Must read differently from refusal.passTimeout — they are different failures."
      )
    case "refusal.engineFailed":
      return String(
        localized: "refusal.engineFailed",
        defaultValue:
          "The recognition engine returned an error; no text was produced. You can try dictating again.",
        bundle: .module,
        comment: "The engine itself failed.")
    case "refusal.emptyTranscript":
      return String(
        localized: "refusal.emptyTranscript",
        defaultValue: "Recognition found speech but produced no text, so nothing was inserted.",
        bundle: .module,
        comment: "Speech was detected but transcribed to nothing.")
    case "refusal.insertionFailed":
      return String(
        localized: "refusal.insertionFailed",
        defaultValue: "The clipboard or paste event could not be prepared, so nothing was sent.",
        bundle: .module,
        comment: "Cause sentence only; the recovery sentence follows as its own key.")
    case "refusal.overflow":
      return String(
        localized: "refusal.overflow",
        defaultValue: "Too many dictations are still being processed. Wait for them to finish.",
        bundle: .module,
        comment: "Too many sessions in flight at once.")
    case "refusal.silentInput.volumeDown":
      return String(
        localized: "refusal.silentInput.volumeDown",
        defaultValue:
          "Your microphone\'s input volume is turned all the way down, so the recording was silent. Raise it in System Settings → Sound → Input.",
        bundle: .module,
        comment:
          "The system input level is at zero. The pane path is macOS\'s own and comes from the glossary."
      )
    case "refusal.silentInput.deadDevice":
      return String(
        localized: "refusal.silentInput.deadDevice",
        defaultValue:
          "No signal at all from the microphone. Check Vocula’s Microphone settings — a headset connected only for playback records nothing.",
        bundle: .module,
        comment:
          "A dead input device, NOT a quiet room. Fixed by a different action from refusal.silentInput.volumeDown, so the two must not converge. Microphone is this app\'s own section name. — the indicator caps at three lines and cuts anything longer. Drawn on the indicator strip, which clamps at three lines; IndicatorChipSizeTests measures every locale against it."
      )
    case "refusal.denied.secureField":
      return String(
        localized: "refusal.denied.secureField",
        defaultValue: "Not inserted: the cursor was in a password field.",
        bundle: .module,
        comment: "The insert was refused because the target was secure.")
    case "refusal.denied.appChanged":
      return String(
        localized: "refusal.denied.appChanged",
        defaultValue: "Not inserted: you switched to another app while it was still transcribing.",
        bundle: .module,
        comment: "Said in terms of what the USER did, not what the app detected.")
    case "refusal.denied.windowChanged":
      return String(
        localized: "refusal.denied.windowChanged",
        defaultValue:
          "Not inserted: you switched to another window while it was still transcribing.",
        bundle: .module,
        comment: "Said in terms of what the USER did.")
    case "refusal.denied.elementChanged":
      return String(
        localized: "refusal.denied.elementChanged",
        defaultValue:
          "Not inserted: you clicked into another field while it was still transcribing.",
        bundle: .module,
        comment: "Said in terms of what the USER did.")
    case "refusal.denied.secureInputRaised":
      return String(
        localized: "refusal.denied.secureInputRaised",
        defaultValue: "Not inserted: secure input turned on while it was still transcribing.",
        bundle: .module,
        comment: "Secure input is macOS\'s own term.")
    default:
      return key
    }
  }

  public static func keys(
    forRawReason raw: String?, historyIsRecording: Bool,
    inputIsSilenced: Bool = false
  ) -> [String]? {
    guard let raw else { return ["refusal.nothingInserted"] }
    if raw == hallucination { return nil }
    if let failure = SessionFailure(rawValue: raw) {
      return keys(
        for: failure, historyIsRecording: historyIsRecording,
        inputIsSilenced: inputIsSilenced)
    }
    if let deny = InsertDenyReason(rawValue: raw) {
      return keys(for: deny, historyIsRecording: historyIsRecording)
    }
    return ["refusal.nothingInserted.unknown"]
  }

  public static func text(
    forRawReason raw: String?, historyIsRecording: Bool,
    inputIsSilenced: Bool = false
  ) -> String? {
    guard let raw else { return text(forKey: "refusal.nothingInserted") }
    if raw == hallucination { return nil }
    if let failure = SessionFailure(rawValue: raw) {
      return text(
        for: failure, historyIsRecording: historyIsRecording,
        inputIsSilenced: inputIsSilenced)
    }
    if let deny = InsertDenyReason(rawValue: raw) {
      return text(for: deny, historyIsRecording: historyIsRecording)
    }
    return String(
      localized: "refusal.nothingInserted.unknown", defaultValue: "Nothing was inserted (\(raw)).",
      bundle: .module,
      comment:
        "An unrecognised stored reason; the argument is a raw enum value and is NEVER translated.")
  }

  public static func keys(
    for failure: SessionFailure, historyIsRecording: Bool,
    inputIsSilenced: Bool = false
  ) -> [String] {
    switch failure {
    case .passTimeout:
      return ["refusal.passTimeout"]
    case .queueTimeout:
      return ["refusal.queueTimeout"]
    case .engineFailed:
      return ["refusal.engineFailed"]
    case .emptyTranscript:
      return ["refusal.emptyTranscript"]
    case .insertionFailed:
      return [
        "refusal.insertionFailed",
        recoveryKey(historyIsRecording: historyIsRecording),
      ]
    case .overflow:
      return ["refusal.overflow"]
    case .silentInput where inputIsSilenced:
      return ["refusal.silentInput.volumeDown"]
    case .silentInput:
      return ["refusal.silentInput.deadDevice"]
    }
  }

  public static func text(
    for failure: SessionFailure, historyIsRecording: Bool,
    inputIsSilenced: Bool = false
  ) -> String {
    keys(
      for: failure, historyIsRecording: historyIsRecording,
      inputIsSilenced: inputIsSilenced
    )
    .map(text(forKey:)).joined(separator: " ")
  }

  public static func keys(
    for reason: InsertDenyReason,
    historyIsRecording: Bool
  ) -> [String] {
    [causeKey(reason), recoveryKey(historyIsRecording: historyIsRecording)]
  }

  private static func causeKey(_ reason: InsertDenyReason) -> String {
    switch reason {
    case .secureField: return "refusal.denied.secureField"
    case .appChanged: return "refusal.denied.appChanged"
    case .windowChanged: return "refusal.denied.windowChanged"
    case .elementChanged: return "refusal.denied.elementChanged"
    case .secureInputRaised: return "refusal.denied.secureInputRaised"
    }
  }

  public static func cause(_ reason: InsertDenyReason) -> String {
    text(forKey: causeKey(reason))
  }

  public static func text(for reason: InsertDenyReason, historyIsRecording: Bool) -> String {
    keys(for: reason, historyIsRecording: historyIsRecording)
      .map(text(forKey:)).joined(separator: " ")
  }
}
