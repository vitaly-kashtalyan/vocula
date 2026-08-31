import AppKit
import VoculaKit

@MainActor
final class VoculaAppDelegate: NSObject, NSApplicationDelegate {
  let menu = MenuBarController()
  let updater = UpdaterController()
  let downloader: ModelDownloader
  lazy var coordinator = AppCoordinator(menu: menu)
  let settingsNavigation = SettingsNavigationModel()
  private var _historyModel: HistoryWindowModel?
  var historyModel: HistoryWindowModel {
    if let model = _historyModel { return model }
    let model = HistoryWindowModel(store: coordinator.historyStore)
    _historyModel = model
    return model
  }
  private let wasFirstLaunch = !AppSettings().hasCompletedOnboarding
  let onboarding = OnboardingModelObservable()

  var presentOnboarding: (() -> Void)? {
    didSet { Task { presentOnboardingIfNeeded() } }
  }
  private var launchDidFinish = false
  private var didDecideOnboarding = false

  override init() {
    let store = ModelStore(
      directory: ApplicationSupport.modelsDirectory,
      fileSystem: SystemModelFileSystem())
    let settings = AppSettings()
    downloader = ModelDownloader(
      store: store,
      requiredModels: { [settings.transcriptionModel, .speechDetector] })
    super.init()
  }

  nonisolated static let isHostingTests = NSClassFromString("XCTestCase") != nil

  nonisolated static let isUITesting = ProcessInfo.processInfo.arguments.contains("-VoculaUITest")

  nonisolated static let isCapturingScreenshots =
    ProcessInfo.processInfo.arguments.contains("-VoculaScreenshot")

  // Tests and the screenshot tool run a SECOND copy of this app, out of
  // DerivedData and under the same bundle identifier. Asking TCC for Input
  // Monitoring or opening the microphone from there rewrites which binary macOS
  // records as holding the grant, so the copy in /Applications silently loses
  // its record key — with no error and no clue when it broke. Guarded at the
  // two places that reach the system, not at each caller, because a caller can
  // always be added.
  nonisolated static let isSecondCopy =
    isHostingTests || isUITesting || isCapturingScreenshots

  static let bindingDefaults: UserDefaults =
    isUITesting
    ? UserDefaults(suiteName: "app.vocula.mac.uitest")!
    : .standard

  static let menuBarIconVisibleKey = "menuBarIconVisible"

  private static var anotherCopyIsRunning: Bool {
    guard !isHostingTests, !isUITesting,
      let id = Bundle.main.bundleIdentifier
    else { return false }
    return NSRunningApplication.runningApplications(withBundleIdentifier: id)
      .contains {
        $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated
      }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    guard !Self.isHostingTests else { return }
    UsageLedger().startTrialIfNeeded()
    AppSettings().appearance.apply()
    if Self.anotherCopyIsRunning {
      NSRunningApplication.runningApplications(
        withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
      )
      .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
      .activate()
      _exit(0)
    }
    downloader.diagnose = { [weak self] kind, detail in
      self?.coordinator.log(kind, detail)
    }
    updater.diagnose = { [weak self] kind, detail in
      self?.coordinator.log(kind, detail)
    }
    updater.gestureIsOpen = { [weak self] in
      guard let self else { return false }
      return self.menu.iconState == .recording || self.menu.iconState == .working
    }
    Task {
      if Self.isUITesting {
        coordinator.startMonitorOnly()
      } else {
        await coordinator.start()
      }
      launchDidFinish = true
      _ = LaunchInterfaceLanguage.code
      presentOnboardingIfNeeded()
      reopenSettingsIfAsked()
      openSettingsIfTheMenuBarIconIsHidden()
      startUpdaterIfAllowed()
    }
  }

  private func startUpdaterIfAllowed() {
    guard
      UpdaterController.mayStart(
        isSecondCopy: Self.isSecondCopy,
        argumentsDisableUpdates: ProcessInfo.processInfo.arguments
          .contains(UpdaterController.disableArgument))
    else { return }
    updater.start()
  }

  private func presentOnboardingIfNeeded() {
    guard launchDidFinish, !didDecideOnboarding, let present = presentOnboarding
    else { return }
    didDecideOnboarding = true
    onboarding.refresh()
    guard wasFirstLaunch || !OnboardingModel.isComplete(onboarding.rows) else { return }
    present()
  }

  private func reopenSettingsIfAsked() {
    guard !Self.isUITesting,
      let raw = UserDefaults.standard.string(forKey: Relaunch.sectionArgument),
      let section = SettingsSection(rawValue: raw)
    else { return }
    openSettings?(section)
  }

  var openSettings: ((SettingsSection) -> Void)?

  static func hasVisibleWindow(_ windows: [NSWindow]) -> Bool {
    windows.contains { $0.isVisible && !($0 is NSPanel) }
  }

  private func openSettingsIfTheMenuBarIconIsHidden() {
    guard !Self.isUITesting,
      UserDefaults.standard.object(forKey: Self.menuBarIconVisibleKey) != nil,
      !UserDefaults.standard.bool(forKey: Self.menuBarIconVisibleKey),
      !Self.hasVisibleWindow(NSApp.windows)
    else { return }
    presentOnboarding?()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !Self.isHostingTests else { return .terminateNow }
    Task { @MainActor in
      await self.coordinator.finishInFlightWork()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows: Bool
  ) -> Bool {
    if !hasVisibleWindows { openMainWindow?() }
    return true
  }

  var openMainWindow: (() -> Void)?

  func applicationWillTerminate(_ notification: Notification) {
    coordinator.shutdown()
    downloader.shutdown()
    // _exit: a normal exit runs ggml's static destructors, which abort.
    _exit(0)
  }
}
