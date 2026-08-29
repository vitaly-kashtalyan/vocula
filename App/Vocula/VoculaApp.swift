import AppKit
import SwiftUI
import VoculaKit
import VoculaWhisper

@main
struct VoculaApp: App {
  @NSApplicationDelegateAdaptor(VoculaAppDelegate.self) private var appDelegate
  @Environment(\.openWindow) private var openWindow
  @AppStorage(VoculaAppDelegate.menuBarIconVisibleKey) private var menuBarIconVisible = true
  private var onboarding: OnboardingModelObservable { appDelegate.onboarding }
  private var settingsNavigation: SettingsNavigationModel { appDelegate.settingsNavigation }

  var body: some Scene {
    onboarding.onAccessibilityGranted = { [weak coordinator = appDelegate.coordinator] in
      coordinator?.reinstallHotkeyAfterPermissionChange()
    }
    onboarding.recordDiagnostic = { [weak coordinator = appDelegate.coordinator] kind, detail in
      coordinator?.log(kind, detail)
    }
    appDelegate.presentOnboarding = { [settingsNavigation, openWindow] in
      settingsNavigation.selection = .permissions
      openWindow(id: Self.mainWindowID)
    }
    appDelegate.openMainWindow = { [openWindow] in
      openWindow(id: Self.mainWindowID)
    }
    appDelegate.openSettings = { [settingsNavigation, openWindow] section in
      settingsNavigation.selection = section
      openWindow(id: Self.mainWindowID)
    }
    appDelegate.coordinator.presentLicence = { [settingsNavigation, openWindow] in
      settingsNavigation.selection = .licence
      openWindow(id: Self.mainWindowID)
    }
    return Group {
      MenuBarExtra(isInserted: $menuBarIconVisible) {
        MenuBarContentView(
          menu: appDelegate.menu, downloader: appDelegate.downloader,
          navigation: settingsNavigation,
          onOpen: { [weak coordinator = appDelegate.coordinator] in
            coordinator?.recheckAccessibility()
          })
      } label: {
        MenuBarLabelView(menu: appDelegate.menu)
      }
      Window(Text(verbatim: "Vocula"), id: Self.mainWindowID) {
        SettingsWindowView(
          navigation: settingsNavigation,
          onboarding: onboarding,
          menu: appDelegate.menu,
          downloader: appDelegate.downloader,
          coordinator: appDelegate.coordinator,
          historyModel: appDelegate.historyModel,
          onModelsReady: {
            await appDelegate.coordinator.modelsDidBecomeReady()
          }
        )
        .onAppear {
          onboarding.refresh()
          NSApp.activate(ignoringOtherApps: true)
        }
      }
      .defaultSize(width: 900, height: 620)
      .defaultPosition(.center)
      .windowResizability(.contentMinSize)
      .windowToolbarStyle(.unified)
      .commands {
        CommandGroup(replacing: .appSettings) {
          Button(MenuCopy.settings) {
            settingsNavigation.selection = .status
            openWindow(id: Self.mainWindowID)
          }
          .keyboardShortcut(",", modifiers: .command)
        }
      }
    }
  }

  static let mainWindowID = "main"
}

private struct MenuBarLabelView: View {
  @ObservedObject var menu: MenuBarController

  var body: some View {
    Group {
      if let mark = menu.iconState.mark {
        Image(nsImage: mark.image)
      } else {
        Image(systemName: menu.iconState.symbol)
      }
    }
    .accessibilityLabel(Text(verbatim: "Vocula"))
    .accessibilityValue(Text(menu.iconState.spokenState))
  }
}

private struct MenuBarContentView: View {
  @ObservedObject var menu: MenuBarController
  @AppStorage(AppSettings.historyEnabledKey)
  private var historyEnabled = AppSettings.historyEnabledDefault
  @AppStorage(AppSettings.languageCodesKey)
  private var storedLanguageCodes = AppSettings.languageCodesDefault
  @AppStorage(AppSettings.autoDetectLanguageKey)
  private var autoDetectLanguage = AppSettings.autoDetectLanguageDefault
  @AppStorage(AppSettings.pinnedLanguageKey)
  private var pinnedLanguage = AppSettings.pinnedLanguageDefault
  @AppStorage(AppSettings.microphonePriorityKey)
  private var microphonePriorityRaw = AppSettings.microphonePriorityDefault

  private var microphonePriority: MicrophonePriorityList {
    get { MicrophonePriorityList(encoded: microphonePriorityRaw) }
    nonmutating set { microphonePriorityRaw = newValue.encoded() }
  }
  let downloader: ModelDownloader
  @ObservedObject var navigation: SettingsNavigationModel
  let onOpen: () -> Void
  @Environment(\.openWindow) private var openWindow

  private var languages: LanguageSelection {
    LanguageSelection(
      stored: storedLanguageCodes, autoDetect: autoDetectLanguage,
      pinned: pinnedLanguage)
  }

  private var orderedLanguages: [WhisperLanguage] {
    let selected = languages.codes
    return selected.compactMap(WhisperLanguages.language(for:))
      + WhisperLanguages.all.filter { !selected.contains($0.code) }
  }

  private func write(_ selection: LanguageSelection) {
    storedLanguageCodes = selection.stored
    autoDetectLanguage = selection.autoDetect
    pinnedLanguage = selection.pinned
  }

  private func openSettings(_ section: SettingsSection) {
    navigation.selection = section
    openWindow(id: VoculaApp.mainWindowID)
  }

  var body: some View {
    Group {
      if case .keyLost(let reason) = menu.iconState {
        Text(verbatim: reason)
        Button(MenuCopy.changeRecordKey) { openSettings(.keyboard) }
        Divider()
      }
      if case .error(let reason) = menu.iconState {
        Text(verbatim: reason)
        if menu.showsDownloadAction {
          Button(MenuCopy.downloadModels) { openSettings(.models) }
        }
        Divider()
      }
      if let last = menu.lastTranscript {
        Button(MenuCopy.copyLastTranscript) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(last, forType: .string)
        }
      }
      Toggle(MenuCopy.recordHistory, isOn: $historyEnabled)
      if menu.historyPaused {
        Text(MenuCopy.historyPaused)
      } else {
        Button(MenuCopy.pauseHistory) { menu.historyPaused = true }
      }
      Button(MenuCopy.history) { openSettings(.history) }
      Divider()
      Button(MenuCopy.keyboard) { openSettings(.keyboard) }
      Menu(MenuCopy.microphone) {
        let connected = menu.inputDevices
        let connectedUIDs = Set(connected.map(\.uid))
        let builtInUID = menu.builtInUID
        let ranked = microphonePriority.reconciled(
          with: connected.map { RankedInputDevice(uid: $0.uid, name: $0.name) },
          builtInUID: builtInUID)
        let activeUID = ranked.firstAvailable(in: connectedUIDs)?.uid
        Picker(
          selection: Binding(
            get: { activeUID },
            set: { chosen in
              guard let chosen else { return }
              microphonePriority = ranked.movedToTop(uid: chosen)
            })
        ) {
          ForEach(ranked.devices, id: \.uid) { device in
            Text(verbatim: device.displayName).tag(String?.some(device.uid))
          }
        } label: {
          EmptyView()
        }
        .pickerStyle(.inline)
      }
      Menu(MenuCopy.languages) {
        Toggle(
          MenuCopy.detectAutomatically,
          isOn: Binding(
            get: { languages.autoDetect },
            set: { write(languages.settingAutoDetect($0)) }))
        Divider()
        ForEach(orderedLanguages) { language in
          Toggle(
            isOn: Binding(
              get: {
                languages.autoDetect
                  ? languages.codes.contains(language.code)
                  : languages.pinned == language.code
              },
              set: { _ in write(languages.toggling(language.code)) }
            )
          ) {
            Text(verbatim: language.titleWithNativeName)
          }
        }
        Divider()
        Button(MenuCopy.allLanguages) { openSettings(.languages) }
      }
      Button(MenuCopy.settings) { openSettings(.status) }
      Button(MenuCopy.reportProblem) { menu.reportProblem() }
      Button(MenuCopy.revealDiagnosticLog) { menu.revealDiagnosticLog() }
      Divider()
      Text(verbatim: Bundle.main.versionLine)
      Button(MenuCopy.quit) {
        NSApplication.shared.terminate(nil)
      }
    }
    .onAppear(perform: onOpen)
  }
}

struct KeyboardSettingsContent: View {
  @ObservedObject var coordinator: AppCoordinator

  var body: some View {
    if let bindingModel = coordinator.bindingModel {
      BindingSettingsView(model: bindingModel)
    } else {
      Text(MenuCopy.startingUp).padding(20)
    }
  }
}
