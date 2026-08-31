import Foundation

enum CommonCopy {
  static let cancel = LocalizedStringResource(
    "common.cancel", defaultValue: "Cancel",
    comment: "Dismisses a dialog without doing anything. Must match what macOS calls Cancel.")
  static let delete = LocalizedStringResource(
    "common.delete", defaultValue: "Delete",
    comment: "Confirms a destructive action in a dialog.")
}

enum HistoryScreenCopy {
  static func noSpeechReadout(_ segments: Int, _ frameProbability: String, _ peak: String)
    -> LocalizedStringResource
  {
    LocalizedStringResource(
      "history.record.noSpeechReadout",
      defaultValue: "No speech · segments \(segments) · frame p \(frameProbability) · peak \(peak)",
      comment:
        "Diagnostic line under a dictation that produced no speech. 'frame p' is a probability and 'peak' an audio level, both already formatted as numbers or an em dash. Keep them short: this is a dense row."
    )
  }
  static func dayWithNothing(_ day: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "history.day.nothing", defaultValue: "\(day) · nothing",
      comment:
        "Accessibility label and tooltip for a day square in the heat map that has no dictations. The argument is a day heading such as Today or a date."
    )
  }
  static let empty = LocalizedStringResource(
    "history.empty", defaultValue: "Nothing recorded yet.",
    comment: "Shown in place of the day's records when there are none.")
  static let deleteDayItem = LocalizedStringResource(
    "history.menu.deleteDay", defaultValue: "Delete This Day…",
    comment: "Menu item removing one day's dictations.")
  static let deleteAllItem = LocalizedStringResource(
    "history.menu.deleteAll", defaultValue: "Delete All History…",
    comment: "Menu item removing every dictation on the Mac.")
  static let deleteMenuHelp = LocalizedStringResource(
    "history.menu.help", defaultValue: "Delete this day, or all history",
    comment: "Tooltip on the trash menu beside a day's heading.")
  static func confirmDeleteDay(_ day: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "history.confirm.deleteDay.title", defaultValue: "Delete \(day)?",
      comment:
        "Dialog title; the argument is a day heading such as Today or a date. It is NOT lower-cased — German capitalises nouns and Turkish has the dotted-I hazard."
    )
  }
  static let deleteAllTitle = LocalizedStringResource(
    "history.confirm.deleteAll.title", defaultValue: "Delete all dictation history?",
    comment: "Dialog title for removing everything.")
  static let deleteAllButton = LocalizedStringResource(
    "history.confirm.deleteAll.button", defaultValue: "Delete All",
    comment: "Confirms removing every dictation.")
  static let deleteAllMessage = LocalizedStringResource(
    "history.confirm.deleteAll.message",
    defaultValue: "Every dictation saved on this Mac will be removed. This cannot be undone.",
    comment: "Dialog body for removing everything.")
  static func copyAccessibility(_ time: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "history.record.copy.accessibility", defaultValue: "Copy the dictation from \(time)",
      comment: "VoiceOver label; the argument is a formatted time of day.")
  }
  static let copyHelp = LocalizedStringResource(
    "history.record.copy.help", defaultValue: "Copy this text",
    comment: "Tooltip on a record's copy button.")
  static func deleteAccessibility(_ time: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "history.record.delete.accessibility",
      defaultValue: "Delete the dictation from \(time)",
      comment: "VoiceOver label; the argument is a formatted time of day.")
  }
  static let deleteHelp = LocalizedStringResource(
    "history.record.delete.help", defaultValue: "Delete this record",
    comment: "Tooltip on a record's delete button.")
  static let heatMapLess = LocalizedStringResource(
    "history.heatMap.less", defaultValue: "Less",
    comment: "Left end of the heat map's density legend.")
  static let heatMapMore = LocalizedStringResource(
    "history.heatMap.more", defaultValue: "More",
    comment: "Right end of the heat map's density legend.")
}

enum LicenceScreenCopy {
  static let licensedTo = LocalizedStringResource(
    "licence.licensedTo", defaultValue: "Licensed to",
    comment: "Row label; the value beside it is the licence holder's own name.")
  static let unlimited = LocalizedStringResource(
    "licence.unlimited",
    defaultValue:
      "Unlimited dictation, on every Mac of yours. Verified right here, with no network connection at all, which is why there is no sign-in and no account.",
    comment:
      "States that LICENCE VERIFICATION is offline. This is a privacy claim about the product and must keep saying that checking the licence makes no network connection. Do NOT widen it to the whole app: Vocula fetches the speech model once and checks for its own updates daily."
  )
  static let personalLicence = LocalizedStringResource(
    "licence.personal",
    defaultValue:
      "It is a personal licence, and it carries your address: please keep it to yourself.",
    comment: "Asks the user not to share their key.")
  static let removeItem = LocalizedStringResource(
    "licence.remove.item", defaultValue: "Remove Licence…",
    comment: "Button opening the remove-licence confirmation.")
  static let removeTitle = LocalizedStringResource(
    "licence.remove.title", defaultValue: "Remove this licence from this Mac?",
    comment: "Confirmation dialog title.")
  static let removeButton = LocalizedStringResource(
    "licence.remove.button", defaultValue: "Remove Licence",
    comment: "Confirms removing the licence.")
  static let removeMessage = LocalizedStringResource(
    "licence.remove.message",
    defaultValue:
      "Vocula will go back to ten dictations a day here. You can paste the key again at any time — it is in your receipt, and this is the only place it is stored.",
    comment: "Confirmation dialog body. The daily number must agree with TrialPolicy.")
  static let clockRow = LocalizedStringResource(
    "licence.clock.row", defaultValue: "Latest date seen",
    comment: "Row label; the value beside it is a date this Mac once reported.")
  static let clockReset = LocalizedStringResource(
    "licence.clock.reset", defaultValue: "Follow the Clock",
    comment: "Button that makes the trial follow the system clock again.")
  static let clockExplained = LocalizedStringResource(
    "licence.clock.explained",
    defaultValue:
      "Your free use is measured against the latest date this Mac has reported, so that setting the clock back does not extend it. That date is in the future. If it was wrong — a flat battery, a restored virtual machine — this puts the trial back on the system clock.",
    comment: "Explains why a wrong clock can end a trial early and what the button does.")
  static let status = LocalizedStringResource(
    "licence.status", defaultValue: "Status",
    comment: "Row label for the trial or licence state.")
  static let freeUse = LocalizedStringResource(
    "licence.freeUse", defaultValue: "Free use",
    comment: "Row label for what the trial still allows.")
  static let offlineCheck = LocalizedStringResource(
    "licence.offlineCheck",
    defaultValue:
      "Vocula checks your key on this Mac, with no network connection at all. That is why there is no sign-in, no account, and no limit on how many of your own Macs one licence will open.",
    comment:
      "A privacy claim about the product: LICENCE VERIFICATION is offline, and must keep saying so. Do NOT widen it to the whole app — the model download and the update check both use the network."
  )
  static let pasteButton = LocalizedStringResource(
    "licence.paste.button", defaultValue: "Paste Licence Key",
    comment: "Reads a licence key from the clipboard.")
  static let clearButton = LocalizedStringResource(
    "licence.clear", defaultValue: "Clear",
    comment: "Empties the licence key field.")
  static let notAKey = LocalizedStringResource(
    "licence.notAKey",
    defaultValue:
      "That is not a Vocula licence key. What was pasted is above — check that the whole key was copied; it is about 120 characters and your mail client may have wrapped it across several lines, which is fine.",
    comment: "Shown when the pasted text does not verify. 120 is the key's own length.")
  static let pasteHint = LocalizedStringResource(
    "licence.paste.hint",
    defaultValue:
      "Copy the key from your receipt, then press the button. Line breaks and spaces do not matter.",
    comment: "Shown above an empty licence field.")
  static let fieldPlaceholder = LocalizedStringResource(
    "licence.field.placeholder", defaultValue: "Paste your licence key here",
    comment: "Placeholder inside the licence key field.")
  static let notActivated = LocalizedStringResource(
    "licence.notActivated", defaultValue: "Not activated",
    comment: "Status shown when no licence key is present.")
  static let notRecognised = LocalizedStringResource(
    "licence.notRecognised", defaultValue: "Not recognised",
    comment: "Status shown when a key is present but does not verify.")
}

enum OnboardingScreenCopy {
  static func rowGranted(_ title: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "onboarding.row.accessibility.granted", defaultValue: "\(title) — granted",
      comment: "VoiceOver label for a permission row; the argument is the row's title.")
  }
  static func rowNotGranted(_ title: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "onboarding.row.accessibility.notGranted", defaultValue: "\(title) — not granted",
      comment: "VoiceOver label for a permission row; the argument is the row's title.")
  }
  static let checkAgain = LocalizedStringResource(
    "onboarding.checkAgain", defaultValue: "Check again",
    comment: "Re-reads every permission's current state.")
  static let granted = LocalizedStringResource(
    "onboarding.state.granted", defaultValue: "Granted",
    comment:
      "Shown beside a permission that macOS has already granted, and as the label of the count above the list. ONE word; it is drawn in small caps by the view, never cased in code."
  )
  static let rechecked = LocalizedStringResource(
    "onboarding.rechecked", defaultValue: "Re-read each time Vocula comes forward",
    comment:
      "Footer under the permissions. Says why there is no Check again button: every permission is read afresh whenever the app becomes active."
  )
  static let updateAutomatically = LocalizedStringResource(
    "onboarding.updateAutomatically", defaultValue: "Update automatically",
    comment:
      "Switch on the Permissions screen, beside 'Open at login'. Lets Vocula check for its own updates. Not a macOS permission — it is our setting."
  )
  static let checkForUpdates = LocalizedStringResource(
    "onboarding.checkForUpdates", defaultValue: "Check Now",
    comment: "Button that asks for an update check immediately."
  )
  static let lastChecked = LocalizedStringResource(
    "onboarding.lastChecked", defaultValue: "Last checked",
    comment:
      "Row label; the value beside it is when a check last SUCCEEDED. A stale date is how someone whose updater is being blocked finds out, because a failed check says nothing on screen."
  )
  static let neverChecked = LocalizedStringResource(
    "onboarding.neverChecked", defaultValue: "Never",
    comment: "Value beside 'Last checked' when no check has ever succeeded on this Mac."
  )
  static let checkedToday = LocalizedStringResource(
    "onboarding.checkedToday", defaultValue: "Today",
    comment: "Value beside 'Last checked' when the last successful check was today."
  )
  static let updatesFooter = LocalizedStringResource(
    "onboarding.updatesFooter",
    defaultValue:
      "While this is on, Vocula asks GitHub once a day whether a newer version exists. Nothing about you or your dictation is sent with it, and nothing is downloaded or installed until you say so.",
    comment:
      "Footer under the update rows. It tells the reader what leaving the switch on costs them: one small request a day. Wraps over several lines."
  )
  static let settingsFooter = LocalizedStringResource(
    "onboarding.settingsFooter", defaultValue: "Dictation works without these.",
    comment:
      "Footer under the two rows that are NOT macOS permissions — launching at login and the 🌐 key. Must keep saying that dictation works without them, or a switched-off row reads as a fault."
  )
  static let keepHistory = LocalizedStringResource(
    "onboarding.keepHistory", defaultValue: "Keep a history of dictations",
    comment: "Switch controlling whether dictations are saved at all.")
  static let privacyFooter = LocalizedStringResource(
    "onboarding.privacyFooter",
    defaultValue:
      "Your dictations never leave this Mac. They are encrypted, and only this Mac can open them — a copy of the file, in a backup or on another computer, stays unreadable. A dictation is deleted a year after it was made.",
    comment:
      "The promise the app is bought for. It states encryption, that the key does not travel, and the retention window; all three must survive translation. The year must agree with HistoryRetention.days."
  )
  static let tileSavedTyping = LocalizedStringResource(
    "history.tile.savedTyping", defaultValue: "saved, not spent typing",
    comment:
      "Caption under a duration. Counterfactual on purpose: it is typing the person did NOT do, never time they spent."
  )
  static let tileCharacters = LocalizedStringResource(
    "history.tile.characters", defaultValue: "characters you didn't type",
    comment: "Caption under a character count.")
  static let tileAverageWords = LocalizedStringResource(
    "history.tile.averageWords", defaultValue: "words on an average day",
    comment: "Caption under a word count, averaged over the days that have dictations.")
  static let tileDictations = LocalizedStringResource(
    "history.tile.dictations", defaultValue: "dictations kept",
    comment: "Caption under the number of dictations in the history.")
  static func tileAccessibility(
    _ figure: String,
    _ caption: LocalizedStringResource
  ) -> LocalizedStringResource {
    LocalizedStringResource(
      "history.tile.accessibility", defaultValue: "\(figure) \(String(localized: caption))",
      comment:
        "VoiceOver label for one figure above the heat map: the number, then its caption. Reorder the two if the number does not come first in your language."
    )
  }

  static let figureSource = LocalizedStringResource(
    "onboarding.figureSource.accessibility", defaultValue: "Where this figure comes from",
    comment: "VoiceOver label for the button opening the typing-rate citation.")
  static let typingTitle = LocalizedStringResource(
    "onboarding.typing.title", defaultValue: "Typing time",
    comment: "Heading of the popover explaining the typing-time figure.")
  static func typingRate(_ wordsPerMinute: Int, _ charactersPerWord: Int)
    -> LocalizedStringResource
  {
    LocalizedStringResource(
      "onboarding.typing.rate",
      defaultValue:
        "How long the same text would take at a keyboard, at \(wordsPerMinute) words a minute — a word being \(charactersPerWord) characters, which is how typing speed has always been counted.",
      comment:
        "Arguments are a words-per-minute rate and a characters-per-word figure, both fixed constants."
    )
  }
  static let typingStudy = LocalizedStringResource(
    "onboarding.typing.study",
    defaultValue:
      "That rate is the average across 168 000 people in Dhakal, Feit, Kristensson and Oulasvirta, “Observations on Typing from 136 Million Keystrokes”, CHI 2018 — the largest measurement there is for an ordinary keyboard.",
    comment:
      "A citation. The authors' names and the paper's title are proper nouns and are NOT translated; the paper's title keeps its own quotation marks."
  )
  static let typingCaveat = LocalizedStringResource(
    "onboarding.typing.caveat",
    defaultValue:
      "They were copying text rather than composing it, and they had come to a typing test of their own accord, so they are quick. Treat it as an estimate.",
    comment: "States the study's limits. Transcription, not composition.")
  static let menuBarIconHidden = LocalizedStringResource(
    "onboarding.menuBarHidden.title", defaultValue: "Vocula's menu bar icon is hidden",
    comment:
      "Row title, shown only when the icon has been dragged out of the menu bar. Menu bar is Apple's own name for it."
  )
  static let showMenuBarIcon = LocalizedStringResource(
    "onboarding.menuBarHidden.show", defaultValue: "Show",
    comment: "Button that puts the menu bar icon back. One word — it sits in a narrow row.")
  static let typingCounts = LocalizedStringResource(
    "onboarding.typing.counts",
    defaultValue: "Counts every dictation that reached the caret, as far back as the history goes.",
    comment: "Says what the figure totals. Only inserted dictations count.")
}

enum MicrophoneScreenCopy {
  static let header = LocalizedStringResource(
    "microphone.header", defaultValue: "In order of preference",
    comment: "Heading over the ranked list of input devices.")
  static let fallbackRule = LocalizedStringResource(
    "microphone.fallbackRule",
    defaultValue: "Vocula records from the first device on this list that is plugged in.",
    comment: "States the fallback rule the ranking exists for.")
  static let volumeIsShared = LocalizedStringResource(
    "microphone.volumeIsShared",
    defaultValue: "Input volume is the microphone's own setting, shared with every app.",
    comment: "Warns that changing the level here changes it system-wide.")
  static let notConnected = LocalizedStringResource(
    "microphone.notConnected", defaultValue: "not connected",
    comment:
      "Marks a ranked device that is absent right now. Lower case: it follows the device's name on the same line."
  )
  static let bluetoothProfile = LocalizedStringResource(
    "microphone.bluetoothProfile",
    defaultValue: "Bluetooth headset profile — transcribed less accurately than the Mac's own.",
    comment: "Warns that the hands-free profile is narrowband. A measured fact, not an opinion.")
  static func moveUp(_ device: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "microphone.moveUp", defaultValue: "Move \(device) up",
      comment: "Button label; the argument is a device name.")
  }
  static func moveDown(_ device: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "microphone.moveDown", defaultValue: "Move \(device) down",
      comment: "Button label; the argument is a device name.")
  }
  static let stop = LocalizedStringResource(
    "microphone.stop", defaultValue: "Stop",
    comment: "Closes the level meter on an on-demand device.")
  static let test = LocalizedStringResource(
    "microphone.test", defaultValue: "Test",
    comment: "Opens the level meter on an on-demand device. A VERB here, not a noun.")
  static let inUse = LocalizedStringResource(
    "microphone.inUse", defaultValue: "IN USE",
    comment: "Badge on the device currently being recorded from. Shown upper-cased by the style;")
  static let inputVolume = LocalizedStringResource(
    "microphone.inputVolume", defaultValue: "Input volume",
    comment: "Row label for the system input level slider.")
  static func veryQuiet(_ percent: Int) -> LocalizedStringResource {
    LocalizedStringResource(
      "microphone.veryQuiet",
      defaultValue:
        "Below \(percent)% the level bars look almost dead, though the recording is still fine.",
      comment: "Reassurance under the volume slider; the argument is a percentage.")
  }
  static let noVolumeControl = LocalizedStringResource(
    "microphone.noVolumeControl", defaultValue: "This device has no volume control of its own.",
    comment: "Shown where the slider would be for a device that offers none.")
  static let couldNotOpen = LocalizedStringResource(
    "microphone.couldNotOpen",
    defaultValue: "This microphone could not be opened to show its level.",
    comment: "The meter failed; dictation may still work.")
  static let listening = LocalizedStringResource(
    "microphone.listening",
    defaultValue:
      "Listening holds this device open. A headset stays in its hands-free profile, which is not stereo.",
    comment: "Explains the cost of the meter on an on-demand device.")
  static let notListening = LocalizedStringResource(
    "microphone.notListening",
    defaultValue:
      "Not listening. Opening this device would take a headset out of stereo, so press Test to see the level.",
    comment:
      "Why the meter is closed by default on an on-demand device. Test is the button's own label.")
}

enum LanguageScreenCopy {
  static let autoDetect = LocalizedStringResource(
    "languages.autoDetect", defaultValue: "Detect the language automatically",
    comment: "Switch: whether a detection pass runs before transcription.")
  static let detectionExplained = LocalizedStringResource(
    "languages.detectionExplained",
    defaultValue:
      "Every phrase is compared against the languages below and transcribed in whichever scores highest.",
    comment: "How detection works when it is on.")
  static let detectionIsRestricted = LocalizedStringResource(
    "languages.detectionIsRestricted",
    defaultValue:
      "The comparison is over YOUR list and nothing else. Whisper's own unrestricted detection is never used: on mixed speech it returns a third language, transcribes in it, and only then reports it.",
    comment: "A measured fact about the engine, not a preference. Whisper is a product name.")
  static let noDetection = LocalizedStringResource(
    "languages.noDetection",
    defaultValue:
      "Every phrase is transcribed in the one language selected below, with no detection pass at all.",
    comment: "How recognition works when detection is off.")
  static let qualityVaries = LocalizedStringResource(
    "languages.qualityVaries",
    defaultValue:
      "Recognition quality varies a great deal between languages. English is the one this app has been measured on.",
    comment:
      "An honesty note. English being the measured language is a fact about this app, and stays true in every translation."
  )
  static func pinAccessibility(_ language: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "languages.pin.accessibility", defaultValue: "Transcribe every phrase in \(language)",
      comment: "VoiceOver label; the argument is a language name.")
  }
  static let pinHelp = LocalizedStringResource(
    "languages.pin.help", defaultValue: "Transcribe every phrase in this language",
    comment: "Tooltip on the pin control.")
  static func removeAccessibility(_ language: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "languages.remove.accessibility", defaultValue: "Remove \(language)",
      comment: "VoiceOver label; the argument is a language name.")
  }
  static let atLeastOne = LocalizedStringResource(
    "languages.atLeastOne", defaultValue: "At least one language is needed.",
    comment: "Tooltip explaining why the last language cannot be removed.")
  static let remove = LocalizedStringResource(
    "languages.remove", defaultValue: "Remove",
    comment: "Tooltip on the remove control.")
  static let selected = LocalizedStringResource(
    "languages.selected", defaultValue: "Selected",
    comment: "Heading over the chosen languages.")
  static let pinnedExplained = LocalizedStringResource(
    "languages.pinnedExplained",
    defaultValue:
      "The filled circle is the language every phrase is transcribed in. The others stay in the list: ⌃⇧L steps through them, and through automatic detection.",
    comment: "⌃⇧L is a key chord and is never translated.")
  static let cycleExplained = LocalizedStringResource(
    "languages.cycleExplained",
    defaultValue: "⌃⇧L steps through this list, and through automatic detection.",
    comment: "⌃⇧L is a key chord and is never translated.")
  static func noMatch(_ search: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "languages.noMatch", defaultValue: "No language matches “\(search)”.",
      comment: "Empty search result; the argument is what was typed, in quotation marks.")
  }
  static let allLanguages = LocalizedStringResource(
    "languages.all", defaultValue: "All languages",
    comment: "Heading over the full list from the engine.")
  static let clearSearch = LocalizedStringResource(
    "languages.clearSearch", defaultValue: "Clear the search",
    comment: "VoiceOver label on the search field's clear button.")
}

enum DiagnosticsScreenCopy {
  static let empty = LocalizedStringResource(
    "diagnostics.empty", defaultValue: "Nothing recorded yet.",
    comment: "Shown when the diagnostic log holds no events.")
  static let revealInFinder = LocalizedStringResource(
    "diagnostics.revealInFinder", defaultValue: "Reveal in Finder",
    comment: "Finder is macOS's own name and is not translated.")
  static let reportProblem = LocalizedStringResource(
    "diagnostics.reportProblem", defaultValue: "Report a Problem…",
    comment: "Same words as the menu bar item; keep them identical.")
  static let clear = LocalizedStringResource(
    "diagnostics.clear", defaultValue: "Clear",
    comment: "Empties the diagnostic log.")
  static let clearTitle = LocalizedStringResource(
    "diagnostics.clear.title", defaultValue: "Clear the diagnostic log?",
    comment: "Confirmation dialog title.")
  static let clearMessage = LocalizedStringResource(
    "diagnostics.clear.message",
    defaultValue:
      "Everything recorded so far is discarded. Useful before reproducing a problem, so the report carries only what happened while it went wrong.",
    comment: "Confirmation dialog body.")
  static let logContents = LocalizedStringResource(
    "diagnostics.logContents",
    defaultValue:
      "The log holds event names and short values only — never dictated text. It is what a report about a key that stopped working, or a dictation that came back empty, has to be read from. “Report a Problem…” opens your mail client with the file attached; nothing is sent until you press Send.",
    comment:
      "A PRIVACY statement: the log never holds dictated text. The quoted item name must match the button's own words, and Send is what the mail client calls its send button."
  )
}

enum KeyboardScreenCopy {
  static func bindingChanged(_ slot: String, _ key: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "binding.announcement.changed", defaultValue: "\(slot) is now \(key)",
      comment:
        "Spoken to VoiceOver after a key is rebound. First argument is the row's title such as Record key, second is the new key or chord such as fn or ⌃⇧L."
    )
  }
  static func hold(_ key: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "keyboard.hold",
      defaultValue:
        "Hold \(key) and speak; let go and the text is inserted. Esc cancels. The language key steps through the languages you have selected and through automatic detection.",
      comment:
        "The argument is a key chord such as fn or ⌃⇧L, which is never translated. Esc is a key name."
    )
  }
  static let pressAnyKey = LocalizedStringResource(
    "keyboard.pressAnyKey", defaultValue: "Press any key",
    comment: "Shown while a binding is being recorded.")
  static func pressNow(_ key: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "keyboard.pressNow", defaultValue: "Press \(key) now",
      comment: "The argument is a key chord, never translated.")
  }
  static let change = LocalizedStringResource(
    "keyboard.change", defaultValue: "Change",
    comment: "Starts recording a new binding. A VERB.")
  static let test = LocalizedStringResource(
    "keyboard.test", defaultValue: "Test",
    comment:
      "Starts the live check on a binding. A VERB, and the same word the Microphone screen uses.")
}

enum ModelScreenCopy {
  static func notDownloaded(_ size: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "models.status.notDownloaded", defaultValue: "\(size) · not downloaded",
      comment:
        "Under a model's name in the picker. The argument is a file size already formatted for the reader's locale, such as 1.62 GB. Keep the separator."
    )
  }
  static func partlyDownloaded(_ size: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "models.status.partlyDownloaded", defaultValue: "\(size) · partly downloaded",
      comment:
        "Under a model's name in the picker when a download stopped part way. The argument is a formatted file size."
    )
  }
  static func damaged(_ size: String, _ version: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "models.status.damaged", defaultValue: "\(size) · \(version) · damaged, load it again",
      comment:
        "Under a model's name when its checksum did not match. First argument is a formatted file size, second is the upstream model version. It is an instruction: the user should download it again."
    )
  }
  static let speechDetector = LocalizedStringResource(
    "models.speechDetector.row", defaultValue: "Speech detector",
    comment: "Row title for the VAD model; must match ModelManifest's display name.")
  static let requiredForTranscription = LocalizedStringResource(
    "models.required", defaultValue: "Required for transcription.",
    comment: "Says the speech detector is not optional.")
  static let downloadMissing = LocalizedStringResource(
    "models.downloadMissing", defaultValue: "Download what is missing",
    comment: "Fetches every model that is not already present.")
  static let fullyLocal = LocalizedStringResource(
    "models.fullyLocal", defaultValue: "Recognition is fully local, after a one-time download.",
    comment: "A PRIVACY claim: nothing is sent for recognition. Must keep saying so.")
  static let load = LocalizedStringResource(
    "models.load", defaultValue: "Load",
    comment: "Brings an already-downloaded model into memory. A VERB.")
  static let licences = LocalizedStringResource(
    "models.licences", defaultValue: "Licences",
    comment: "Heading over the third-party licence notices.")
  static func engineCredit(_ family: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "models.engineCredit", defaultValue: "\(family) engine",
      comment:
        "The argument is an engine's product NAME — Whisper, Parakeet — and is never translated.")
  }
  static let updaterCredit = LocalizedStringResource(
    "models.updaterCredit", defaultValue: "Updates",
    comment:
      "Row label in the third-party notices block on Settings → Models; the value beside it names the update framework and its licence. Not a model and not a recognition engine — it is listed here because this is where the app shows every third-party notice."
  )
  static let fullLicenceTexts = LocalizedStringResource(
    "models.fullLicenceTexts", defaultValue: "Full licence texts…",
    comment: "Opens the bundled THIRD-PARTY.txt. Showing these is a licence obligation.")
}

enum StatusScreenCopy {
  static let openPermissions = LocalizedStringResource(
    "status.alert.openPermissions", defaultValue: "Open Permissions",
    comment: "Button on an alert row; opens Settings → Permissions.")
  static let openModels = LocalizedStringResource(
    "status.alert.openModels", defaultValue: "Open Models",
    comment: "Button on an alert row; opens Settings → Models.")
  static let openKeyboard = LocalizedStringResource(
    "status.alert.openKeyboard", defaultValue: "Open Keyboard",
    comment: "Button on an alert row; opens Settings → Keyboard.")
  static let holdToDictate = LocalizedStringResource(
    "status.holdToDictate", defaultValue: "Hold to dictate",
    comment: "Under the record key on the dashboard hero.")
  static let escCancels = LocalizedStringResource(
    "status.escCancels", defaultValue: "Esc → cancel",
    comment: "Esc is a key name and is not translated.")
  static func tryPrompt(_ key: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "status.tryPrompt", defaultValue: "Click here, then hold \(key) and say something",
      comment: "The argument is a key chord, never translated.")
  }
  static let tryAccessibility = LocalizedStringResource(
    "status.try.accessibility", defaultValue: "Try dictation",
    comment: "VoiceOver label for the scratch field on the dashboard.")
  static let historyPausedHere = LocalizedStringResource(
    "status.historyPaused", defaultValue: "History is paused while this is focused.",
    comment: "Shown while the scratch field holds focus.")
  static let nothingSavedHere = LocalizedStringResource(
    "status.nothingSaved", defaultValue: "Nothing dictated here is saved to history.",
    comment: "Shown while the scratch field does not hold focus.")
  static let privacyFooter = LocalizedStringResource(
    "status.privacyFooter",
    defaultValue:
      "Nothing leaves this Mac. Dictations are encrypted, and only this computer can open them.",
    comment:
      "The promise the app is bought for. Must keep saying that nothing is sent and that the key does not travel."
  )
}

enum AppearanceScreenCopy {
  static let noSettingNeeded = LocalizedStringResource(
    "appearance.noSettingNeeded",
    defaultValue:
      "The design needs no such setting to look right: one accent works in both appearances, and every colour resolves against whatever the Mac is set to. This exists because a Mac's setting and a person's preference are not the same thing — a system on Auto goes dark at sunset.",
    comment: "Auto is what macOS calls its automatic appearance; use that system's own word.")
  static let interfaceLanguage = LocalizedStringResource(
    "appearance.interfaceLanguage", defaultValue: "Interface Language",
    comment:
      "Row label for the language the WINDOW is written in — not the languages dictation recognises, which are in the Languages section."
  )
  static let matchSystem = LocalizedStringResource(
    "appearance.language.matchSystem", defaultValue: "Match System",
    comment:
      "Picker row: follow whatever macOS resolves, which is the absence of an override rather than a language."
  )
  static let interfaceLanguageExplained = LocalizedStringResource(
    "appearance.language.explained",
    defaultValue:
      "This is the language Vocula's own windows are written in. What it can transcribe is separate, and lives in Languages.",
    comment:
      "Footer distinguishing the interface language from the dictation languages. Languages is this app's own section name."
  )
  static let relaunchNeeded = LocalizedStringResource(
    "appearance.language.relaunchNeeded",
    defaultValue: "The new language appears when Vocula next starts.",
    comment: "Footer shown after the interface language is changed.")
  static let relaunchNow = LocalizedStringResource(
    "appearance.language.relaunchNow", defaultValue: "Quit and Reopen",
    comment: "Button that restarts the app so the new interface language takes effect.")
  static let stripKeepsItsGrey = LocalizedStringResource(
    "appearance.stripKeepsItsGrey",
    defaultValue:
      "The strip above the Dock keeps its own fixed grey either way. It is drawn over other applications' windows, where the system appearance says nothing about what is behind it.",
    comment: "Dock is macOS's own name and is not translated.")
}

enum SidebarCopy {
  static let showSectionNames = LocalizedStringResource(
    "sidebar.showNames", defaultValue: "Show section names",
    comment: "Tooltip on the sidebar toggle when it is collapsed.")
  static let collapseToIcons = LocalizedStringResource(
    "sidebar.collapse", defaultValue: "Collapse to icons",
    comment: "Tooltip on the sidebar toggle when names are shown.")
}

extension KeyboardScreenCopy {
  static let listeningForAKey = LocalizedStringResource(
    "keyboard.state.listening", defaultValue: "Listening for a key",
    comment: "Row state while a binding is being recorded.")
  static let waitingForTheKey = LocalizedStringResource(
    "keyboard.state.waiting", defaultValue: "Waiting for the key",
    comment: "Row state while the live check waits for a press.")
  static let notTested = LocalizedStringResource(
    "keyboard.state.notTested", defaultValue: "Not tested",
    comment: "Row state before the live check has been run.")
  static let arrivesCorrectly = LocalizedStringResource(
    "keyboard.state.working", defaultValue: "Arrives correctly",
    comment: "Row state: press and release both reached the tap.")
  static let neverArrives = LocalizedStringResource(
    "keyboard.state.nothingArrived", defaultValue: "Never arrives",
    comment: "Row state: nothing reached the tap at all.")
  static let onlyPress = LocalizedStringResource(
    "keyboard.state.pressWithoutRelease", defaultValue: "Only the press arrives",
    comment:
      "Row state: the release never came. Distinct from the release-only state by more than a word."
  )
  static let onlyRelease = LocalizedStringResource(
    "keyboard.state.releaseWithoutPress", defaultValue: "Only the release arrives",
    comment:
      "Row state: the press never came. Distinct from the press-only state by more than a word.")
}

extension LicenceScreenCopy {
  static let buy = LocalizedStringResource(
    "licence.buy", defaultValue: "Buy a licence…",
    comment: "Opens the website. The checkout itself is English and out of scope.")
}

extension LanguageScreenCopy {
  static let searchPrompt = LocalizedStringResource(
    "languages.searchPrompt", defaultValue: "Search for any language",
    comment: "Placeholder in the language search field.")
}

extension StatusScreenCopy {
  static func modelDownloading(_ percent: Int, _ size: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "status.card.model.downloading",
      defaultValue: "downloading \(percent)% · \(size)",
      comment: "Model card detail; arguments are a percentage and an already-formatted size.")
  }
  static func modelReady(_ size: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "status.card.model.ready", defaultValue: "ready · \(size)",
      comment: "Model card detail; the argument is an already-formatted size.")
  }
  static func modelNotDownloaded(_ size: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "status.card.model.notDownloaded",
      defaultValue: "not downloaded · \(size)",
      comment: "Model card detail; the argument is an already-formatted size.")
  }
  static let autoDetectOn = LocalizedStringResource(
    "status.card.languages.autoDetect", defaultValue: "auto-detect on",
    comment: "Languages card detail.")
  static func pinnedTo(_ language: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "status.card.languages.pinned", defaultValue: "pinned to \(language)",
      comment: "Languages card detail; the argument is a language name.")
  }
  static let noMicrophoneRanked = LocalizedStringResource(
    "status.card.microphone.noneRanked", defaultValue: "no microphone is ranked yet",
    comment: "Microphone card detail.")
  static let noRankedConnected = LocalizedStringResource(
    "status.card.microphone.noneConnected", defaultValue: "no ranked microphone is connected",
    comment: "Microphone card detail.")
  static let chosenInVocula = LocalizedStringResource(
    "status.card.microphone.chosen", defaultValue: "chosen in Vocula",
    comment: "Microphone card detail: the top-ranked device is the one in use.")
  static let lowerPriority = LocalizedStringResource(
    "status.card.microphone.lower", defaultValue: "using a lower-priority microphone",
    comment: "Microphone card detail: the top-ranked device is absent.")
}

extension LanguageScreenCopy {
  static let autoShort = LocalizedStringResource(
    "languages.auto.short", defaultValue: "Auto",
    comment:
      "The auto-detect stop in the ⌃⇧L language cycle, shown in the indicator beside language names. Drawn on the indicator strip, which clamps at three lines; IndicatorChipSizeTests measures every locale against it."
  )
}

extension KeyboardScreenCopy {
  static func collides(_ shortcut: String) -> LocalizedStringResource {
    LocalizedStringResource(
      "keyboard.collides",
      defaultValue:
        "Collides with a system shortcut: \(shortcut). You can still assign it — whose key matters more is your call.",
      comment:
        "The argument is a macOS Keyboard Shortcuts row name, which comes from the glossary. The second sentence is deliberate: this is a warning, not a refusal."
    )
  }
}

extension KeyboardScreenCopy {
  static let noKeyArrived = LocalizedStringResource(
    "keyboard.noKeyArrived",
    defaultValue:
      "No key arrived. Accessibility may be off, or another app is taking keys first — try Test.",
    comment:
      "Shown when a capture timed out with nothing. Test is this screen's own button label; Accessibility is macOS's pane name."
  )
  static let notSaved = LocalizedStringResource(
    "keyboard.notSaved", defaultValue: "Not saved.",
    comment:
      "Precedes a refusal sentence of its own. TWO sentences, never a prefix glued to a fragment.")
  static let warningPrefix = LocalizedStringResource(
    "keyboard.warning", defaultValue: "Warning.",
    comment:
      "Precedes a warning sentence of its own. TWO sentences, never a prefix glued to a fragment.")
}

extension HistoryScreenCopy {
  static let deleteAllFailed = LocalizedStringResource(
    "history.deleteAll.failed", defaultValue: "The history could not be deleted.",
    comment:
      "The disk write failed; memory has been restored, so the screen still shows what is really there."
  )
  static let deleteDayFailed = LocalizedStringResource(
    "history.deleteDay.failed", defaultValue: "That day could not be deleted.",
    comment: "The disk write failed for one day; memory has been restored.")
}

extension StatusScreenCopy {
  static let systemDefaultDevice = LocalizedStringResource(
    "status.systemDefaultDevice", defaultValue: "System default",
    comment:
      "Placeholder for the input device before the scan has answered. macOS's own term for the default input."
  )
}
