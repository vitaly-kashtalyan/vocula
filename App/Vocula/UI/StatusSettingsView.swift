import SwiftUI
import VoculaKit
import VoculaWhisper

struct StatusSettingsView: View {
  @ObservedObject var onboarding: OnboardingModelObservable
  @ObservedObject var menu: MenuBarController
  @ObservedObject var coordinator: AppCoordinator
  @ObservedObject var downloader: ModelDownloader
  @ObservedObject var historyModel: HistoryWindowModel
  let openSection: (SettingsSection) -> Void

  @State private var trying = ""
  @FocusState private var tryingFocused: Bool
  @State private var pauseBeforeTrying = false

  @AppStorage(AppSettings.languageCodesKey)
  private var languageCodes = AppSettings.languageCodesDefault
  @AppStorage(AppSettings.autoDetectLanguageKey)
  private var autoDetect = AppSettings.autoDetectLanguageDefault
  @AppStorage(AppSettings.pinnedLanguageKey)
  private var pinnedLanguage = AppSettings.pinnedLanguageDefault
  @AppStorage(AppSettings.microphonePriorityKey)
  private var microphonePriorityRaw = AppSettings.microphonePriorityDefault

  private var microphonePriority: MicrophonePriorityList {
    MicrophonePriorityList(encoded: microphonePriorityRaw)
  }
  @State private var devices: [AudioInputDevice] = []
  @State private var defaultDeviceName = String(localized: StatusScreenCopy.systemDefaultDevice)

  var body: some View {
    Section { hero.dashboardRow() }
    if !alerts.isEmpty {
      Section {
        ForEach(alerts) { alert in
          AlertRow(alert: alert, act: { openSection(alert.section) })
            .dashboardRow()
        }
      }
    }
    Section { tryIt.dashboardRow() }
    Section { cards.dashboardRow() }
      .task { await readDevices() }
      .refreshOnActivate { Task { await readDevices() } }
    Section { footer.dashboardRow() }
      .task { await historyModel.refreshDays() }
      .task {
        if downloader.statuses.isEmpty { await downloader.refreshStatuses() }
      }
  }

  private var hero: some View {
    VStack(spacing: 16) {
      Waveform2a()
        .frame(width: 300, height: 48)
      VStack(spacing: 8) {
        HStack(spacing: 10) {
          KeycapView(name: recordKeyName)
          Text(StatusScreenCopy.holdToDictate)
            .font(Theme.heroLine)
            .foregroundStyle(Theme.textPrimary)
        }
        Text(StatusScreenCopy.escCancels)
          .font(Theme.readout)
          .foregroundStyle(Theme.textMuted)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 6)
  }

  private var tryIt: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: trying.isEmpty ? "mic" : "text.quote")
          .font(.system(size: 11))
        Group {
          if trying.isEmpty {
            Text(StatusScreenCopy.tryPrompt(recordKeyName))
          } else {
            Text(verbatim: trying)
          }
        }
        .font(.system(size: 12, weight: .medium))
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      .foregroundStyle(Theme.windowRamp)
      .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .cardSurface(
        Theme.cardBackground,
        border: tryingFocused ? Theme.accent : Theme.cardBorder,
        lineWidth: tryingFocused ? 2 : 0.5
      )
      .overlay(alignment: .bottomLeading) {
        TextField(text: $trying) { Text(verbatim: "") }
          .textFieldStyle(.plain)
          .focused($tryingFocused)
          .frame(width: 1, height: 1)
          .opacity(0.01)
          .accessibilityLabel(Text(StatusScreenCopy.tryAccessibility))
          .accessibilityIdentifier("status.tryDictation")
      }
      .contentShape(Rectangle())
      .onTapGesture { tryingFocused = true }

      Group {
        if tryingFocused {
          Text(StatusScreenCopy.historyPausedHere)
        } else {
          Text(StatusScreenCopy.nothingSavedHere)
        }
      }
      .font(Theme.readout)
      .foregroundStyle(Theme.textMuted)
    }
    .onChange(of: menu.iconState) { was, now in
      if tryingFocused, was == .idle, now == .recording { trying = "" }
    }
    .onChange(of: tryingFocused) { _, focused in
      if focused {
        pauseBeforeTrying = menu.historyPaused
        menu.historyPaused = true
      } else {
        menu.historyPaused = pauseBeforeTrying
      }
    }
    .onDisappear {
      if tryingFocused { menu.historyPaused = pauseBeforeTrying }
    }
  }

  private var recordKeyName: String {
    coordinator.bindingModel?.name(of: .record) ?? "fn"
  }

  struct Alert: Identifiable {
    let id: String
    let title: String
    let detail: String
    let section: SettingsSection
    let actionTitle: LocalizedStringResource
  }

  private var alerts: [Alert] {
    var found = OnboardingModel.incomplete(onboarding.rows)
      .map { row in
        Alert(
          id: row.kind.rawValue, title: row.title,
          detail: row.settingsPath ?? row.explanation,
          section: .permissions, actionTitle: StatusScreenCopy.openPermissions)
      }
    switch menu.iconState {
    case .error(let reason):
      found.append(
        Alert(
          id: "error", title: reason,
          detail: "",
          section: menu.showsDownloadAction ? .models : .keyboard,
          actionTitle: menu.showsDownloadAction
            ? StatusScreenCopy.openModels
            : StatusScreenCopy.openKeyboard))
    case .keyLost(let reason):
      found.append(
        Alert(
          id: "keyLost", title: reason, detail: "",
          section: .keyboard, actionTitle: StatusScreenCopy.openKeyboard))
    default:
      break
    }
    return found
  }

  private struct AlertRow: View {
    let alert: Alert
    let act: () -> Void

    var body: some View {
      HStack(alignment: .top, spacing: 11) {
        Circle()
          .frame(width: 7, height: 7)
          .foregroundStyle(Theme.warning)
          .padding(.top, 5)
        VStack(alignment: .leading, spacing: 3) {
          Text(verbatim: alert.title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
          if !alert.detail.isEmpty {
            Text(verbatim: alert.detail)
              .font(Theme.readout)
              .foregroundStyle(Theme.textSecondary)
          }
        }
        Spacer(minLength: 8)
        Button(action: act) { Text(alert.actionTitle) }
      }
      .padding(.horizontal, 15)
      .padding(.vertical, 13)
      .cardSurface(Theme.warningBackground, border: Theme.warningBorder)
    }
  }

  private var cards: some View {
    HStack(alignment: .top, spacing: 11) {
      Button {
        openSection(.models)
      } label: {
        StatusCard(
          label: SettingsSection.models.title, value: model.displayName,
          detail: modelDetail, detailIsAccented: modelIsReady)
      }
      Button {
        openSection(.languages)
      } label: {
        StatusCard(
          label: SettingsSection.languages.title, value: languageNames, detail: languageDetail)
      }
      Button {
        openSection(.microphone)
      } label: {
        StatusCard(
          label: SettingsSection.microphone.title, value: microphoneName, detail: microphoneDetail)
      }
    }
    .buttonStyle(.plain)
  }

  private var model: ModelDescriptor {
    ModelManifest.descriptor(for: AppSettings().transcriptionModel)
  }

  private var modelIsReady: Bool { downloader.statuses[model.id] == .ready }

  private var modelDetail: String {
    let size = model.byteSize.formatted(.byteCount(style: .file).locale(.interface))
    if let fraction = downloader.fraction[model.id], downloader.isDownloading {
      return String(
        localized: StatusScreenCopy.modelDownloading(
          Int(fraction * 100), size))
    }
    switch downloader.statuses[model.id] {
    case .ready: return String(localized: StatusScreenCopy.modelReady(size))
    case .none: return size
    default: return String(localized: StatusScreenCopy.modelNotDownloaded(size))
    }
  }

  private var languages: LanguageSelection {
    LanguageSelection(stored: languageCodes, autoDetect: autoDetect, pinned: pinnedLanguage)
  }

  private var languageNames: String {
    languages.codes
      .map { code in
        WhisperLanguages.language(for: code).map { $0.nativeName ?? $0.displayName }
          ?? code.uppercased(with: .invariant)
      }
      .joined(separator: ", ")
  }

  private var languageDetail: String {
    guard !languages.autoDetect else {
      return String(localized: StatusScreenCopy.autoDetectOn)
    }
    let pinned = WhisperLanguages.language(for: languages.pinned)?.displayName ?? languages.pinned
    return String(localized: StatusScreenCopy.pinnedTo(pinned))
  }

  private func readDevices() async {
    let scanned = await Task.detached(priority: .userInitiated) {
      let devices = AudioInputDevices.all
      let builtIn = AudioInputDevices.builtInID
        .flatMap { id in devices.first { $0.id == id }?.name }
      return (devices, builtIn)
    }.value
    devices = scanned.0
    defaultDeviceName =
      scanned.1
      ?? String(
        localized: "status.builtInMicrophone",
        defaultValue: "the built-in microphone",
        comment:
          "Stands in for a device name when macOS will not give one. Lower case: it appears inside a sentence."
      )
  }

  private var microphoneName: String {
    let connectedUIDs = Set(devices.map(\.uid))
    return microphonePriority.firstAvailable(in: connectedUIDs)?.name ?? defaultDeviceName
  }

  private var microphoneDetail: String {
    guard let top = microphonePriority.devices.first else {
      return String(localized: StatusScreenCopy.noMicrophoneRanked)
    }
    let connectedUIDs = Set(devices.map(\.uid))
    guard let chosen = microphonePriority.firstAvailable(in: connectedUIDs) else {
      return String(localized: StatusScreenCopy.noRankedConnected)
    }
    return String(
      localized: chosen.uid == top.uid
        ? StatusScreenCopy.chosenInVocula : StatusScreenCopy.lowerPriority)
  }

  private var footer: some View {
    HStack(alignment: .top, spacing: 14) {
      Text(StatusScreenCopy.privacyFooter)
        .font(.system(size: 11.5))
        .foregroundStyle(Theme.textMuted)
      Spacer(minLength: 8)
      Text(
        verbatim: CountedText.text(HistoryCopy.records(count: historyCount)) + " · "
          + CountedText.text(HistoryCopy.retentionDays(count: HistoryRetention.days))
      )
      .font(Theme.readout)
      .foregroundStyle(Theme.textMuted)
      .fixedSize()
    }
  }

  private var historyCount: Int {
    historyModel.days.reduce(0) { $0 + $1.count }
  }
}

private struct Waveform2a: View {
  private static let quiet: [CGFloat] = [2, 4, 8, 14, 6, 18, 10, 24, 16, 6, 12, 20, 30, 16, 8, 14]
  private static let loud: [CGFloat] = [
    26, 18, 6, 12, 22, 34, 20, 10, 16, 28, 38, 22, 12, 18,
    32, 24, 14, 6,
  ]
  private static let tail: [CGFloat] = [20, 28, 14, 8, 16, 6, 4, 10, 4, 2, 4, 2, 2, 4, 2, 2]

  var body: some View {
    HStack(alignment: .center, spacing: 5) {
      bars(Self.quiet, colour: Theme.textMuted.opacity(0.55))
      bars(Self.loud, colour: Theme.accent)
      bars(Self.tail, colour: Theme.textMuted.opacity(0.55))
    }
  }

  private func bars(_ heights: [CGFloat], colour: Color) -> some View {
    HStack(alignment: .center, spacing: 5) {
      ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
        Capsule()
          .frame(width: 1, height: height)
          .foregroundStyle(colour)
      }
    }
  }
}
