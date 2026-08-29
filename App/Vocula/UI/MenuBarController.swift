import AppKit
import SwiftUI
import VoculaKit

enum KeyLossRecovery {
  static func next(
    current: MenuIconState,
    accessibilityGranted: Bool,
    revokedNotice: String,
    tapInstalled: @autoclosure () -> Bool
  ) -> MenuIconState {
    guard accessibilityGranted else {
      if case .keyLost = current { return current }
      return .keyLost(revokedNotice)
    }
    guard case .keyLost = current else { return current }
    return tapInstalled() ? .idle : current
  }
}

enum MenuIconState: Equatable {
  case idle
  case recording
  case working
  case error(String)
  case keyLost(String)

  var mark: MenuBarMark? {
    switch self {
    case .idle: return .idle
    case .recording: return .recording
    case .working, .error, .keyLost: return nil
    }
  }

  var spokenState: LocalizedStringResource {
    switch self {
    case .idle:
      return LocalizedStringResource(
        "menu.spoken.idle", defaultValue: "ready",
        comment: "VoiceOver value for the menu bar icon: nothing is happening.")
    case .recording:
      return LocalizedStringResource(
        "menu.spoken.recording", defaultValue: "recording",
        comment: "VoiceOver value for the menu bar icon: the microphone is open.")
    case .working:
      return LocalizedStringResource(
        "menu.spoken.working", defaultValue: "transcribing",
        comment: "VoiceOver value for the menu bar icon: recognition is running.")
    case .error:
      return LocalizedStringResource(
        "menu.spoken.error", defaultValue: "needs attention",
        comment: "VoiceOver value for the menu bar icon: something is wrong and the icon says so.")
    case .keyLost:
      return LocalizedStringResource(
        "menu.spoken.keyLost",
        defaultValue: "the record key is not arriving",
        comment: "VoiceOver value for the menu bar icon: the event tap is not delivering the key.")
    }
  }

  var symbol: String {
    switch self {
    case .idle: return "mic"
    case .recording: return "mic.fill"
    case .working: return "waveform"
    case .error: return "exclamationmark.triangle"
    case .keyLost: return "keyboard.badge.ellipsis"
    }
  }
}

@MainActor
final class MenuBarController: ObservableObject {
  @Published var iconState: MenuIconState = .idle
  @Published var showsDownloadAction = false
  @Published var lastTranscript: String?

  @Published private(set) var inputDevices: [AudioInputDevice] = []
  @Published private(set) var builtInUID = ""
  private var deviceList: AudioDeviceListMonitor?
  private let settings = AppSettings()

  func watchInputDevices() {
    guard deviceList == nil else { return }
    deviceList = AudioDeviceListMonitor(diagnose: AudioDiagnostics.record) { [weak self] in
      Task { @MainActor in await self?.refreshInputDevices() }
    }
    Task { @MainActor in await refreshInputDevices() }
  }

  func refreshInputDevices() async {
    let scanned = await Task.detached(priority: .utility) {
      let devices = AudioInputDevices.all
      let builtIn =
        AudioInputDevices.builtInID
        .flatMap { id in devices.first { $0.id == id }?.uid } ?? ""
      return (devices, builtIn)
    }.value
    inputDevices = scanned.0
    builtInUID = scanned.1
  }

  var historyPaused: Bool {
    get { settings.sessionOnlyPause }
    set {
      objectWillChange.send()
      settings.sessionOnlyPause = newValue
    }
  }

  static var accessibilityRevoked: String {
    String(
      localized: "menu.inputMonitoringRevoked",
      defaultValue:
        "Accessibility is no longer granted, so the record key does nothing. Grant it again in \(OnboardingModel.accessibilityPath).",
      comment: "Menu bar message; the argument is a macOS System Settings pane path.")
  }

  static var modelsNotDownloaded: String {
    String(
      localized: "menu.modelsNotDownloaded",
      defaultValue: "Models are not downloaded yet.",
      comment:
        "Menu bar message and Status alert title: dictation cannot run until the weights are on disk."
    )
  }

  static var tapNotInstalled: String {
    String(
      localized: "menu.tapNotInstalled",
      defaultValue:
        "Accessibility is granted, but the event tap could not be installed. Restart Vocula.",
      comment:
        "Menu bar message shown when the permission is present but the tap still refused to install."
    )
  }

  static var tapInstallFailed: String {
    String(
      localized: "menu.tapInstallFailed",
      defaultValue:
        "The record key could not be installed, so the shortcut does nothing. Grant Accessibility in \(OnboardingModel.accessibilityPath), then restart Vocula.",
      comment: "Menu bar message; the argument is a macOS System Settings pane path.")
  }

  func explainKeyLoss(secureInputActive: Bool) -> String {
    guard secureInputActive else {
      return String(
        localized: "menu.keyLoss",
        defaultValue:
          "The event monitor was repeatedly disabled; key events may have been missed. Open the binding settings and run the live check.",
        comment: "Menu bar message when the event tap kept being disabled.")
    }
    return String(
      localized: "menu.keyLoss.secureInput",
      defaultValue:
        "The event monitor was repeatedly disabled; key events may have been missed. Secure input is currently active. Open the binding settings and run the live check.",
      comment: "As menu.keyLoss, but secure input was on at the time.")
  }

  static let diagnosticLogURL = ApplicationSupport.directory
    .appendingPathComponent("diagnostics.json")

  func revealDiagnosticLog() {
    NSWorkspace.shared.activateFileViewerSelecting([Self.diagnosticLogURL])
  }

  func reportProblem() {
    let body = String(
      localized: "report.body",
      defaultValue: """
        Describe what happened, and what you expected instead.

        The attached file is Vocula's diagnostic log: a list of events (when a dictation started and stopped, whether a download succeeded, why an insert was refused) with the app version and your macOS version. It contains none of your dictated text — that is not written to it, by construction.

        Nothing has been sent yet. Read the attachment, remove anything you would rather not share, and send when you are ready.

        """,
      comment:
        "Body of a problem-report email. The second paragraph is a privacy promise and must keep saying that the dictated text is not in the attachment."
    )
    let items: [Any] = [body, Self.diagnosticLogURL]
    guard let service = NSSharingService(named: .composeEmail),
      service.canPerform(withItems: items)
    else {
      revealDiagnosticLog()
      return
    }
    service.subject = String(
      localized: "report.subject",
      defaultValue: "Vocula problem report",
      comment: "Subject line of a problem-report email.")
    service.perform(withItems: items)
  }
}
