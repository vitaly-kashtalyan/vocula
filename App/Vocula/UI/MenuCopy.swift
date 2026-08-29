import Foundation

enum MenuCopy {
  static let settings = LocalizedStringResource(
    "menu.item.settings", defaultValue: "Settings…",
    comment: "Menu bar item opening the settings window.")
  static let changeRecordKey = LocalizedStringResource(
    "menu.item.changeRecordKey", defaultValue: "Change the record key…",
    comment: "Menu bar item shown when the record key stopped arriving.")
  static let downloadModels = LocalizedStringResource(
    "menu.item.downloadModels", defaultValue: "Download models…",
    comment: "Menu bar item shown when the models are missing.")
  static let copyLastTranscript = LocalizedStringResource(
    "menu.item.copyLastTranscript", defaultValue: "Copy the last transcript",
    comment: "Menu bar item; puts the previous dictation on the clipboard.")
  static let recordHistory = LocalizedStringResource(
    "menu.item.recordHistory", defaultValue: "Record history",
    comment: "Menu bar switch: whether dictations are saved at all.")
  static let historyPaused = LocalizedStringResource(
    "menu.item.historyPaused", defaultValue: "Paused until the app restarts.",
    comment: "Menu bar line shown in place of the pause item once paused.")
  static let pauseHistory = LocalizedStringResource(
    "menu.item.pauseHistory", defaultValue: "Pause history until restart",
    comment: "Menu bar item; stops saving dictations for this run only.")
  static let history = LocalizedStringResource(
    "menu.item.history", defaultValue: "History…",
    comment: "Menu bar item opening the History section.")
  static let keyboard = LocalizedStringResource(
    "menu.item.keyboard", defaultValue: "Keyboard…",
    comment: "Menu bar item opening the Keyboard section.")
  static let microphone = LocalizedStringResource(
    "menu.item.microphone", defaultValue: "Microphone",
    comment: "Menu bar submenu of input devices; must match the sidebar's Microphone.")
  static let languages = LocalizedStringResource(
    "menu.item.languages", defaultValue: "Languages",
    comment: "Menu bar submenu of recognition languages; must match the sidebar's.")
  static let detectAutomatically = LocalizedStringResource(
    "menu.item.detectAutomatically", defaultValue: "Detect the language automatically",
    comment: "Menu bar switch inside the Languages submenu.")
  static let allLanguages = LocalizedStringResource(
    "menu.item.allLanguages", defaultValue: "All languages…",
    comment: "Menu bar item opening the full language picker.")
  static let reportProblem = LocalizedStringResource(
    "menu.item.reportProblem", defaultValue: "Report a Problem…",
    comment: "Menu bar item composing a problem-report email.")
  static let revealDiagnosticLog = LocalizedStringResource(
    "menu.item.revealDiagnosticLog", defaultValue: "Reveal the Diagnostic Log in Finder",
    comment: "Menu bar item; Finder is macOS's own name and is not translated.")
  static let quit = LocalizedStringResource(
    "menu.item.quit", defaultValue: "Quit",
    comment: "Menu bar item; must match what macOS calls Quit on this system.")
  static let startingUp = LocalizedStringResource(
    "menu.startingUp", defaultValue: "Starting up…",
    comment: "Placeholder shown in the window before the app has finished launching.")
}
