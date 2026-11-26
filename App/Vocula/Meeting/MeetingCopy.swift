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
      "Checkable item at the top of the Copy Transcript submenu, and a toggle in the sheet that shows a meeting's transcript in the Meetings section. When checked, a copied transcript includes the user's own lines (what their microphone heard); when unchecked, only the other participants' lines, for someone who only listened. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )

  static func meetingSpeakerLabel(_ speaker: MeetingSpeaker) -> String {
    if speaker == .me { return String(localized: meetingSpeakerMe) }
    if speaker == .others { return String(localized: meetingSpeakerOthers) }
    return speaker.number.map { String(localized: meetingSpeakerNumbered($0)) } ?? speaker.rawValue
  }

  static func meetingStart(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(.interface))
  }

  static func meetingLength(_ duration: TimeInterval) -> String {
    Duration.seconds(max(0, duration.rounded())).formatted(
      .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated).locale(.interface))
  }

  static func transcriptRow(for listing: MeetingListing) -> LocalizedStringResource {
    guard let name = listing.title else {
      return transcriptRow(startedAt: listing.startedAt, duration: listing.duration)
    }
    let length = meetingLength(listing.duration)
    return LocalizedStringResource(
      "meeting.transcript.namedRow", defaultValue: "\(name) · \(length)",
      comment:
        "One row of the Copy Transcript submenu for a meeting the user named: the name the user typed, then how long it lasted (already formatted). Drawn on one menu line that does not wrap; keep the separator short."
    )
  }

  static func transcriptRow(startedAt: Date, duration: TimeInterval) -> LocalizedStringResource {
    let when = meetingStart(startedAt)
    let length = meetingLength(duration)
    return LocalizedStringResource(
      "meeting.transcript.row", defaultValue: "\(when) · \(length)",
      comment:
        "One row of the Copy Transcript submenu: when the meeting started (date and time, already formatted), then how long it lasted (already formatted). Drawn on one menu line that does not wrap; keep the separator short."
    )
  }

  static let meetingSpeakerMe = LocalizedStringResource(
    "meeting.speaker.me", defaultValue: "Me",
    comment:
      "Label of the user's own lines in a meeting transcript: what the microphone heard. Shown in the Meetings section's transcript sheet, and pasted or exported as text wherever the user puts it, often into an AI chat; one short word."
  )

  static let meetingSpeakerOthers = LocalizedStringResource(
    "meeting.speaker.others", defaultValue: "Others",
    comment:
      "Label of the other participants' lines in a meeting transcript: what the other apps played, the people on the call; also the call's lines that could not be given to one speaker. Shown in the Meetings section's transcript sheet, and pasted or exported as text; one short word."
  )

  static func meetingSpeakerNumbered(_ number: Int) -> LocalizedStringResource {
    LocalizedStringResource(
      "meeting.speaker.numbered", defaultValue: "Speaker \(number)",
      comment:
        "Label of one person on the call in a meeting transcript, numbered in the order they first spoke; the argument is that number, an identifier, not a count. Shown in the Meetings section's transcript sheet, and pasted or exported as text wherever the user puts it, often into an AI chat; one short word and the number."
    )
  }

  private static func percent(_ value: Int) -> String {
    (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)).locale(.interface))
  }

  static func speakerModelDownloading(_ value: Int) -> LocalizedStringResource {
    let done = percent(value)
    return LocalizedStringResource(
      "meeting.status.speakerModelDownloading",
      defaultValue: "Downloading the speaker model — \(done); transcription follows.",
      comment:
        "Line in the meeting's own menu bar menu and in the footer of the Meetings section of the Vocula window while the model that tells the people on a call apart downloads; recorded meetings are turned into text only once it has arrived. The argument is how much of it has arrived, already formatted as a percent. In the menu it is drawn on one line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
    )
  }

  static func meetingTranscribing(_ value: Int) -> LocalizedStringResource {
    let done = percent(value)
    return LocalizedStringResource(
      "meeting.status.transcribing", defaultValue: "Transcribing meetings — \(done)",
      comment:
        "Menu line while Vocula turns recorded meetings into text; the argument is how much is done, already formatted as a percent. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
    )
  }

  static func meetingTranscription(_ value: MeetingTranscription) -> [LocalizedStringResource] {
    switch value {
    case .running(let percent, _, _): [meetingTranscribing(percent)]
    case .finished(let transcribed, let failed):
      (transcribed > 0 ? [transcriptReady] : []) + (failed > 0 ? [transcriptionFailed] : [])
    }
  }

  static let transcriptUnreadable = LocalizedStringResource(
    "meeting.status.transcriptUnreadable", defaultValue: "This transcript could not be read.",
    comment:
      "Line shown after a meeting's saved text could not be opened, so nothing was copied, opened or exported: in the meeting's own menu bar menu after Copy Transcript, or in the Meetings section of the Vocula window; also spoken by VoiceOver. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
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

  static let meetingsListFailed = LocalizedStringResource(
    "meetings.failure.list", defaultValue: "Meetings could not be read.",
    comment:
      "Line in the Meetings section of the Vocula window, and spoken by VoiceOver, when the encrypted meetings could not be opened (for example the keychain refused the key). Shown as a row of its own, above the list when there is one; a long translation wraps."
  )

  static let meetingNotSaved = LocalizedStringResource(
    "meetings.failure.notSaved", defaultValue: "The change could not be saved.",
    comment:
      "Line in the Meetings section of the Vocula window, and spoken by VoiceOver, when renaming, pinning or deleting a meeting could not be written to disk. Shown as a row of its own, above the list when there is one; a long translation wraps."
  )

  static let meetingExportFailed = LocalizedStringResource(
    "meetings.failure.export", defaultValue: "The file could not be written.",
    comment:
      "Line in the Meetings section of the Vocula window, and spoken by VoiceOver, when exporting a meeting's transcript to the file the user chose failed. Shown as a row of its own, above the list when there is one; a long translation wraps."
  )

  static let meetingsSection = LocalizedStringResource(
    "settings.section.meetings", defaultValue: "Meetings (Beta)",
    comment:
      "Sidebar section and the window's title while it shows: the list of recorded meetings. The feature is in beta; use the language's usual word for beta. Drawn in the sidebar, which clips a long title."
  )

  static let meetingsReading = LocalizedStringResource(
    "meetings.reading", defaultValue: "Reading meetings…",
    comment:
      "Line in the Meetings section of the Vocula window while the encrypted list of meetings is being read, before it first appears."
  )

  static let meetingsEmpty = LocalizedStringResource(
    "meetings.empty", defaultValue: "No meetings yet",
    comment:
      "Line in the Meetings section of the Vocula window when no meeting has been recorded."
  )

  static let meetingStatusTranscribed = LocalizedStringResource(
    "meetings.status.transcribed", defaultValue: "Transcribed",
    comment:
      "Status of one meeting in the list of the Meetings section of the Vocula window: its transcript is ready. Short; drawn at the end of the row's last line, after the date (when the meeting has a name) and the length (when known)."
  )

  static let meetingStatusWaiting = LocalizedStringResource(
    "meetings.status.waiting", defaultValue: "Waiting for transcription",
    comment:
      "Status of one meeting in the list of the Meetings section of the Vocula window: recorded, not turned into text yet. The longest of the three statuses; drawn at the end of the row's last line, after the date (when the meeting has a name) and the length (when known); keep it short."
  )

  static let meetingShowsTime = LocalizedStringResource(
    "meeting.menu.showsTime", defaultValue: "Show Recording Time",
    comment:
      "Menu item with a checkmark in the meeting's own menu bar menu while a meeting records. When it is off, the meeting's menu bar item shows only its symbol, without the running time of the recording, for example while the screen is being shared. Drawn on one menu line that does not wrap: a longer translation widens the whole menu, so keep it as short as the meaning allows."
  )

  static let meetingsShowTime = LocalizedStringResource(
    "meetings.showsTime", defaultValue: "Show recording time in the menu bar",
    comment:
      "Switch in the Meetings section of the Vocula window. When it is off, the meeting's menu bar item shows only its symbol while a meeting records, without the running time, for example so that people watching a shared screen do not see it."
  )

  static func meetingStatusTranscribing(_ value: Int) -> LocalizedStringResource {
    let done = percent(value)
    return LocalizedStringResource(
      "meetings.status.transcribing", defaultValue: "Transcribing — \(done)",
      comment:
        "Status of one meeting in the list of the Meetings section of the Vocula window while it is being turned into text, in place of the status saying it waits for transcription; the argument is how much of this meeting is done, already formatted as a percent. Drawn at the end of the row's last line, after the date (when the meeting has a name) and the length (when known); keep it short."
    )
  }

  static let meetingStatusRecording = LocalizedStringResource(
    "meetings.status.recording", defaultValue: "Recording",
    comment:
      "Status of one meeting in the list of the Meetings section of the Vocula window: it is being recorded right now. Short; drawn at the end of the row's last line."
  )

  static let meetingPinned = LocalizedStringResource(
    "meetings.pinned", defaultValue: "Pinned",
    comment:
      "Spoken by VoiceOver for the pin symbol on a pinned meeting's row in the Meetings section of the Vocula window: a pinned meeting is kept and cannot be deleted. Never drawn."
  )

  static let meetingOpen = LocalizedStringResource(
    "meetings.action.open", defaultValue: "Open",
    comment:
      "Item in one meeting's menu in the Meetings section of the Vocula window: show its transcript."
  )

  static let meetingRename = LocalizedStringResource(
    "meetings.action.rename", defaultValue: "Rename…",
    comment:
      "Item in one meeting's menu in the Meetings section of the Vocula window: give the meeting a name. The ellipsis means a field follows."
  )

  static let meetingPin = LocalizedStringResource(
    "meetings.action.pin", defaultValue: "Pin",
    comment:
      "Item in one meeting's menu in the Meetings section of the Vocula window: keep the meeting at the top and protect it from deletion."
  )

  static let meetingUnpin = LocalizedStringResource(
    "meetings.action.unpin", defaultValue: "Unpin",
    comment:
      "Item in one meeting's menu in the Meetings section of the Vocula window: undo Pin, so the meeting can be deleted again."
  )

  static let meetingExport = LocalizedStringResource(
    "meetings.action.export", defaultValue: "Export…",
    comment:
      "Item in one meeting's menu in the Meetings section of the Vocula window, and a button in its transcript sheet: save the transcript as a Markdown file. The ellipsis means a save panel follows."
  )

  static let meetingCopy = LocalizedStringResource(
    "meetings.action.copy", defaultValue: "Copy",
    comment:
      "Item in one meeting's menu in the Meetings section of the Vocula window: put the transcript on the clipboard as Markdown."
  )

  static let meetingDelete = LocalizedStringResource(
    "meetings.action.delete", defaultValue: "Delete…",
    comment:
      "Item in one meeting's menu in the Meetings section of the Vocula window: remove the meeting. The ellipsis means a confirmation follows."
  )

  static let meetingRenameTitle = LocalizedStringResource(
    "meetings.rename.title", defaultValue: "Rename Meeting",
    comment:
      "Title of the alert that names a meeting in the Meetings section of the Vocula window."
  )

  static let meetingRenameSave = LocalizedStringResource(
    "meetings.rename.save", defaultValue: "Save",
    comment:
      "Button in the alert that names a meeting: keep the name typed."
  )

  static let meetingRenameField = LocalizedStringResource(
    "meetings.rename.field", defaultValue: "Name",
    comment:
      "Label of the text field in the alert that names a meeting: spoken by VoiceOver, usually not drawn (the field shows the meeting's date as its placeholder). One short word."
  )

  static let meetingDeleteTitle = LocalizedStringResource(
    "meetings.delete.title", defaultValue: "Delete this meeting?",
    comment:
      "Title of the confirmation before deleting a meeting in the Meetings section of the Vocula window."
  )

  static let meetingDeleteMessage = LocalizedStringResource(
    "meetings.delete.message",
    defaultValue: "Its transcript and any audio are removed. This cannot be undone.",
    comment:
      "Message of the confirmation before deleting a meeting: what is lost, and that it is permanent."
  )

  static let meetingsDeleteWaits = LocalizedStringResource(
    "meetings.deleteWaits",
    defaultValue: "Deleting is unavailable until meetings finish transcribing.",
    comment:
      "Footer in the Meetings section of the Vocula window while recorded meetings are being turned into text: Delete is disabled until that ends."
  )

  static let meetingSheetClose = LocalizedStringResource(
    "meetings.sheet.close", defaultValue: "Close",
    comment:
      "Button that closes the sheet showing a meeting's transcript."
  )

  static func meetingActions(for title: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "meetings.actionsFor", defaultValue: "Actions for \(title)",
      comment:
        "Spoken by VoiceOver for the menu button at the end of a meeting's row in the Meetings section; the argument is the meeting's name or its date. Also shown as the button's tooltip, which wraps rather than clips."
    )
  }
}
