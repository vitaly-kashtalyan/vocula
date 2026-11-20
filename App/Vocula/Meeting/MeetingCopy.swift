import Foundation
import VoculaKit

extension MenuCopy {
  static let recordMeeting = LocalizedStringResource(
    "menu.item.recordMeeting", defaultValue: "Record Meeting (Beta)",
    comment:
      "Item in Vocula's menu bar menu; starts recording a meeting: the microphone and the sound other apps play. \"(Beta)\" marks unfinished work. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )
  static let stopMeeting = LocalizedStringResource(
    "menu.item.stopMeeting", defaultValue: "Stop Meeting",
    comment:
      "Item in Vocula's menu bar menu and in the meeting's own menu bar menu; ends the meeting recording. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )
  static let dismissMeetingNotice = LocalizedStringResource(
    "menu.item.dismissMeetingNotice", defaultValue: "Dismiss",
    comment:
      "Item in the meeting's menu bar menu after a meeting ended, after recorded meetings were turned into text, or after a transcript could not be read; clears those lines, and hides that menu bar item unless meetings are still being turned into text. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )

  static func meetingItemLabel(_ label: MeetingStatusRules.Label) -> LocalizedStringResource {
    switch label {
    case .recording: meetingLabel
    case .transcribing: transcribingLabel
    case .idle: meetingLabelNotice
    }
  }

  static let copyTranscript = LocalizedStringResource(
    "menu.item.copyTranscript", defaultValue: "Copy Transcript",
    comment:
      "Submenu in Vocula's menu bar menu, under the item that records a meeting; lists the meetings already turned into text, and choosing one copies its transcript. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )

  static let copyIncludesMe = LocalizedStringResource(
    "menu.item.copyIncludesMe", defaultValue: "Include My Lines",
    comment:
      "Checkable item at the top of the Copy Transcript submenu. When checked, a copied transcript includes the user's own lines (what their microphone heard); when unchecked, only the other participants' lines, for someone who only listened. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )

  static func transcriptRow(startedAt: Date, duration: TimeInterval) -> LocalizedStringResource {
    let when = startedAt.formatted(
      Date.FormatStyle(date: .abbreviated, time: .shortened).locale(.interface))
    let length = Duration.seconds(max(0, duration.rounded())).formatted(
      .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated).locale(.interface))
    return LocalizedStringResource(
      "meeting.transcript.row", defaultValue: "\(when) · \(length)",
      comment:
        "One row of the Copy Transcript submenu: when the meeting started (date and time, already formatted), then how long it lasted (already formatted). Drawn on one menu line that does not wrap; keep the separator short."
    )
  }

  static let meetingSpeakerMe = LocalizedStringResource(
    "meeting.speaker.me", defaultValue: "Me",
    comment:
      "Label of the user's own lines in a copied meeting transcript: what the microphone heard. Pasted as text wherever the user pastes it, often into an AI chat; one short word."
  )

  static let meetingSpeakerOthers = LocalizedStringResource(
    "meeting.speaker.others", defaultValue: "Others",
    comment:
      "Label of the other participants' lines in a copied meeting transcript: what the other apps played, the people on the call. Pasted as text wherever the user pastes it; one short word."
  )

  static func meetingTranscribing(_ percent: Int) -> LocalizedStringResource {
    let done = (Double(percent) / 100).formatted(
      .percent.precision(.fractionLength(0)).locale(.interface))
    return LocalizedStringResource(
      "meeting.status.transcribing", defaultValue: "Transcribing meetings — \(done)",
      comment:
        "Menu line while Vocula turns recorded meetings into text; the argument is how much is done, already formatted as a percent. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
    )
  }

  static func meetingTranscription(_ value: MeetingTranscription) -> [LocalizedStringResource] {
    switch value {
    case .running(let percent): [meetingTranscribing(percent)]
    case .finished(let transcribed, let failed):
      (transcribed > 0 ? [transcriptReady] : []) + (failed > 0 ? [transcriptionFailed] : [])
    }
  }

  static let transcriptUnreadable = LocalizedStringResource(
    "meeting.status.transcriptUnreadable", defaultValue: "This transcript could not be read.",
    comment:
      "Line in the meeting's own menu bar menu after the user chose a meeting in Copy Transcript, in Vocula's menu bar menu, and its saved text could not be opened, so nothing was copied; also spoken by VoiceOver. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )

  private static let transcribingLabel = LocalizedStringResource(
    "meeting.status.labelTranscribing", defaultValue: "Vocula is transcribing meetings",
    comment:
      "VoiceOver label of the meeting's menu bar item while recorded meetings are being turned into text. Spoken, never drawn. \"Vocula\" is never translated."
  )

  private static let transcriptReady = LocalizedStringResource(
    "meeting.status.transcriptReady", defaultValue: "Meeting transcript ready",
    comment:
      "Line in the meeting's own menu bar menu after recorded meetings were turned into text, which Copy Transcript in Vocula's menu bar menu now lists; also spoken by VoiceOver. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )

  private static let transcriptionFailed = LocalizedStringResource(
    "meeting.status.transcriptionFailed",
    defaultValue:
      "Some meetings could not be transcribed; Vocula will try again after the next meeting.",
    comment:
      "Menu line when some recorded meetings could not be turned into text; their recordings are kept and retried after the next meeting ends. Also spoken by VoiceOver. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )

  static func meetingSince(_ date: Date) -> LocalizedStringResource {
    let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.interface))
    return LocalizedStringResource(
      "meeting.status.since", defaultValue: "Recording since \(time)",
      comment:
        "Menu line while a meeting records, fixed at its start; the argument is a time of day, already formatted. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
    )
  }

  static func meetingWarning(_ warning: MeetingWarning) -> LocalizedStringResource {
    switch warning {
    case .waitingForPermission: waitingForPermission
    case .microphoneNotOpened: microphoneNotOpened
    case .microphoneStopped: microphoneStopped
    case .noSystemAudio: noSystemAudio
    case .noSystemAudioYet: noSystemAudioYet
    case .autoStopSoon: autoStopSoon
    case .cannotSave: cannotSave
    }
  }

  static func meetingNotice(_ notice: MeetingNotice) -> LocalizedStringResource {
    switch notice {
    case .autoStopped: autoStopped
    case .endedBySleep: endedBySleep
    case .cannotStart: cannotStart
    }
  }

  private static let meetingLabel = LocalizedStringResource(
    "meeting.status.label", defaultValue: "Vocula is recording a meeting",
    comment:
      "VoiceOver label of the meeting's menu bar item while a meeting records; also announced by VoiceOver when a meeting starts. Spoken, never drawn. \"Vocula\" is never translated."
  )
  private static let meetingLabelNotice = LocalizedStringResource(
    "meeting.status.labelNotice", defaultValue: "Vocula is not recording a meeting",
    comment:
      "VoiceOver label of the meeting's menu bar item when no meeting records and none is being turned into text, while the item still says why it is there: a meeting ended or failed to start, a transcript is ready, or one could not be made or read. Also announced by VoiceOver when the user stops a meeting. Spoken, never drawn. \"Vocula\" is never translated."
  )
  private static let waitingForPermission = LocalizedStringResource(
    "meeting.status.waitingForPermission",
    defaultValue:
      "Waiting for permission to record other apps. Answer the macOS dialog; your microphone is recorded meanwhile.",
    comment:
      "Menu line while macOS's own System Audio Recording dialog is unanswered; also spoken by VoiceOver when it appears. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )
  private static let microphoneNotOpened = LocalizedStringResource(
    "meeting.status.microphoneNotOpened",
    defaultValue:
      "Your microphone is not recorded: a meeting does not open a Bluetooth or iPhone microphone, and none other is chosen. Other apps are recorded.",
    comment:
      "Menu line for the whole meeting: why the microphone is not recorded and what still is; also spoken by VoiceOver. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )
  private static let microphoneStopped = LocalizedStringResource(
    "meeting.status.microphoneStopped",
    defaultValue: "The microphone stopped. Vocula keeps trying to reopen it.",
    comment:
      "Menu line while the microphone is lost or failed to open; also spoken by VoiceOver when it appears. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )
  private static let noSystemAudio = LocalizedStringResource(
    "meeting.status.noSystemAudio", defaultValue: "Vocula hears no other app.",
    comment:
      "Menu line while the system-audio track delivers nothing; also spoken by VoiceOver when it appears. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )
  private static let noSystemAudioYet = LocalizedStringResource(
    "meeting.status.noSystemAudioYet",
    defaultValue:
      "Vocula hasn't heard any other app yet. If your call has sound, check System Audio Recording in Privacy & Security.",
    comment:
      "Menu line after a minute without any sound from other apps; worded to be true whether or not permission was denied. \"System Audio Recording\" and \"Privacy & Security\" are Apple's names: write them as a Mac set to this language shows them (see Localization/glossary.md). Also spoken by VoiceOver. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )
  private static let autoStopSoon = LocalizedStringResource(
    "meeting.status.autoStopSoon",
    defaultValue:
      "Nothing has been heard for 14 minutes. The recording stops in a minute unless there is sound.",
    comment:
      "Menu line in the last minute before the silence stop; also spoken by VoiceOver when it appears. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )
  private static let cannotSave = LocalizedStringResource(
    "meeting.status.cannotSave",
    defaultValue:
      "Part of the recording could not be saved. Vocula keeps trying; check that the disk has free space.",
    comment:
      "Menu line while chunks fail to be written; also spoken by VoiceOver when it appears. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )
  private static let autoStopped = LocalizedStringResource(
    "meeting.status.autoStopped",
    defaultValue:
      "The meeting stopped by itself after 15 minutes without sound. What was recorded is kept.",
    comment:
      "Menu line after the meeting ended, shown until Dismiss or the next recording; also spoken by VoiceOver when it appears. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )
  private static let endedBySleep = LocalizedStringResource(
    "meeting.status.endedBySleep",
    defaultValue: "The meeting stopped when the Mac went to sleep. What was recorded is kept.",
    comment:
      "Menu line after the meeting ended, shown until Dismiss or the next recording; also spoken by VoiceOver when it appears. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )
  private static let cannotStart = LocalizedStringResource(
    "meeting.status.cannotStart",
    defaultValue:
      "The meeting did not start: Vocula could not reach its key in the login keychain or could not write to disk.",
    comment:
      "Menu line after Record failed, shown until Dismiss or the next recording; also spoken by VoiceOver when it appears. \"login keychain\" is Apple's name: write it as a Mac set to this language shows it (see Localization/glossary.md). Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )
}
