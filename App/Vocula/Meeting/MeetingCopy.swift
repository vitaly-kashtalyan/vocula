import Foundation
import VoculaKit

extension MenuCopy {
  static let recordMeeting = LocalizedStringResource(
    "menu.item.recordMeeting", defaultValue: "Record Meeting (Beta)",
    comment:
      "Item in Vocula's menu bar menu; starts recording a meeting: the microphone and the sound other apps play. \"(Beta)\" marks unfinished work. Menu line: does not wrap."
  )
  static let stopMeeting = LocalizedStringResource(
    "menu.item.stopMeeting", defaultValue: "Stop Meeting",
    comment:
      "Item in Vocula's menu bar menu and in the meeting's own menu bar menu; ends the meeting recording. Menu line: does not wrap."
  )
  static let dismissMeetingNotice = LocalizedStringResource(
    "menu.item.dismissMeetingNotice", defaultValue: "Dismiss",
    comment:
      "Item in the meeting's menu bar menu after the meeting ended; hides that menu bar item. Menu line: does not wrap."
  )

  static func meetingStatusLabel(recording: Bool) -> LocalizedStringResource {
    recording ? meetingLabel : meetingLabelNotice
  }

  static func meetingSince(_ date: Date) -> LocalizedStringResource {
    let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.interface))
    return LocalizedStringResource(
      "meeting.status.since", defaultValue: "Recording since \(time)",
      comment:
        "Menu line while a meeting records, fixed at its start; the argument is a time of day, already formatted. Does not wrap."
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
      "VoiceOver label of the meeting's menu bar item while a meeting records; spoken, never drawn. \"Vocula\" is never translated."
  )
  private static let meetingLabelNotice = LocalizedStringResource(
    "meeting.status.labelNotice", defaultValue: "Vocula is not recording a meeting",
    comment:
      "VoiceOver label of the meeting's menu bar item after a meeting ended or failed to start, while the item still says why; spoken, never drawn. \"Vocula\" is never translated."
  )
  private static let waitingForPermission = LocalizedStringResource(
    "meeting.status.waitingForPermission",
    defaultValue:
      "Waiting for permission to record other apps. Answer the macOS dialog; your microphone is recorded meanwhile.",
    comment:
      "Menu line while macOS's own System Audio Recording dialog is unanswered; also spoken by VoiceOver when it appears. Does not wrap."
  )
  private static let microphoneNotOpened = LocalizedStringResource(
    "meeting.status.microphoneNotOpened",
    defaultValue:
      "Your microphone is not recorded: a meeting does not open a Bluetooth or iPhone microphone, and none other is chosen. Other apps are recorded.",
    comment:
      "Menu line for the whole meeting: why the microphone is not recorded and what still is; also spoken by VoiceOver. Does not wrap."
  )
  private static let microphoneStopped = LocalizedStringResource(
    "meeting.status.microphoneStopped",
    defaultValue: "The microphone stopped. Vocula keeps trying to reopen it.",
    comment:
      "Menu line while the microphone is lost or failed to open; also spoken by VoiceOver when it appears. Does not wrap."
  )
  private static let noSystemAudio = LocalizedStringResource(
    "meeting.status.noSystemAudio", defaultValue: "Vocula hears no other app.",
    comment:
      "Menu line while the system-audio track delivers nothing; also spoken by VoiceOver when it appears. Does not wrap."
  )
  private static let noSystemAudioYet = LocalizedStringResource(
    "meeting.status.noSystemAudioYet",
    defaultValue:
      "Vocula hasn't heard any other app yet. If your call has sound, check System Audio Recording in Privacy & Security.",
    comment:
      "Menu line after a minute without any sound from other apps; worded to be true whether or not permission was denied. Both pane names are Apple's own, as that Mac shows them. Also spoken by VoiceOver. Does not wrap."
  )
  private static let autoStopSoon = LocalizedStringResource(
    "meeting.status.autoStopSoon",
    defaultValue:
      "Nothing has been heard for 14 minutes. The recording stops in a minute unless there is sound.",
    comment:
      "Menu line in the last minute before the silence stop; also spoken by VoiceOver when it appears. Does not wrap."
  )
  private static let cannotSave = LocalizedStringResource(
    "meeting.status.cannotSave",
    defaultValue:
      "Part of the recording could not be saved. Vocula keeps trying; check that the disk has free space.",
    comment:
      "Menu line while chunks fail to be written; also spoken by VoiceOver when it appears. Does not wrap."
  )
  private static let autoStopped = LocalizedStringResource(
    "meeting.status.autoStopped",
    defaultValue:
      "The meeting stopped by itself after 15 minutes without sound. What was recorded is kept.",
    comment:
      "Menu line after the meeting ended, shown until Dismiss or the next recording; also spoken by VoiceOver when it appears. Does not wrap."
  )
  private static let endedBySleep = LocalizedStringResource(
    "meeting.status.endedBySleep",
    defaultValue: "The meeting stopped when the Mac went to sleep. What was recorded is kept.",
    comment:
      "Menu line after the meeting ended, shown until Dismiss or the next recording; also spoken by VoiceOver when it appears. Does not wrap."
  )
  private static let cannotStart = LocalizedStringResource(
    "meeting.status.cannotStart",
    defaultValue:
      "The meeting did not start: Vocula could not reach its key in the login keychain or could not write to disk.",
    comment:
      "Menu line after Record failed, shown until Dismiss or the next recording; also spoken by VoiceOver when it appears. \"login keychain\" is Apple's name. Does not wrap."
  )
}
