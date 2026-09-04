import SwiftUI
import VoculaKit

@MainActor
final class OnboardingModelObservable: ObservableObject {
  @Published var rows: [OnboardingRow] = []

  var globeKeyNeeded: Bool {
    BindingStore(defaults: VoculaAppDelegate.bindingDefaults)
      .primary.modifiers.contains(.function)
  }
  @AppStorage("globeKeyDone") private var globeKeyDone = false
  var onAccessibilityGranted: (() -> Void)?
  @Published var openFailure: String?
  private var microphonePromptDidNotAppear = false
  var recordDiagnostic: ((String, String) -> Void)?
  private var loggedMicrophoneStatus: OnboardingStatus?

  init() {
    LoginItem.registerIfNeverAsked()
    refresh()
  }

  func refresh() {
    let previousAccessStatus = rows.first { $0.kind == .accessibility }?.status
    let snapshot = PermissionState.current()
    if loggedMicrophoneStatus != snapshot.microphone, let recordDiagnostic {
      loggedMicrophoneStatus = snapshot.microphone
      recordDiagnostic("permission.microphone", "state=\(snapshot.microphone.rawValue)")
    }
    let microphone =
      snapshot.microphone == .unknown && microphonePromptDidNotAppear
      ? .promptDidNotAppear : snapshot.microphone
    rows = OnboardingModel.rows(
      microphone: microphone,
      accessibility: snapshot.accessibility,
      autostart: snapshot.autostart,
      globeKeyNeeded: globeKeyNeeded,
      globeKeyDone: globeKeyDone)
    if previousAccessStatus != .granted, snapshot.accessibility == .granted {
      onAccessibilityGranted?()
    }
    if OnboardingModel.isComplete(rows) {
      AppSettings().hasCompletedOnboarding = true
    }
  }

  func act(on row: OnboardingRow) {
    openFailure = nil
    switch row.kind {
    case .microphone where row.status == .missing:
      Task { report(await PermissionState.open(.microphone), row) }
    case .microphone where row.status == .restricted:
      Task { report(await PermissionState.open(.screenTime), row) }
    case .microphone:
      Task {
        let granted = await PermissionState.requestMicrophone()
        if !granted, PermissionState.microphone() == .unknown {
          microphonePromptDidNotAppear = true
        }
        refresh()
      }
    case .accessibility: Task { report(await PermissionState.requestAccessibility(), row) }
    case .autostart:
      LoginItem.recordUserChoice()
      if row.status == .granted {
        LoginItem.unregister()
      } else {
        let result = LoginItem.register()
        if result == .needsUserApproval {
          Task { report(await PermissionState.open(.loginItems), row) }
        }
      }
    case .globeKey:
      globeKeyDone = true
      Task { report(await PermissionState.open(.keyboard), row) }
    }
    refresh()
  }

  private func report(_ opened: Bool, _ row: OnboardingRow) {
    guard !opened else { return }
    let path = row.settingsPath ?? OnboardingModel.privacyAndSecurityPath
    openFailure = String(
      localized: "onboarding.openFailed",
      defaultValue: "macOS did not open System Settings. Open it yourself: \(path)",
      comment: "The argument is a System Settings pane path, in Apple's own wording.")
  }
}

struct PermissionsSettingsSection: View {
  @ObservedObject var model: OnboardingModelObservable
  @ObservedObject var updater: UpdaterController
  @AppStorage(VoculaAppDelegate.menuBarIconVisibleKey) private var menuBarIconVisible = true

  private var permissions: [OnboardingRow] {
    model.rows.filter { OnboardingModel.blockingKinds.contains($0.kind) }
  }
  private var settings: [OnboardingRow] {
    model.rows.filter { !OnboardingModel.blockingKinds.contains($0.kind) }
  }
  private var grantedCount: Int {
    permissions.filter { $0.status == .granted }.count
  }
  private var tally: String {
    "\(grantedCount) / \(permissions.count)"
  }

  var body: some View {
    if let failure = model.openFailure {
      Section { Text(verbatim: failure).foregroundStyle(.red) }
    }
    if !menuBarIconVisible {
      Section {
        LabeledContent {
          Button(OnboardingScreenCopy.showMenuBarIcon) { menuBarIconVisible = true }
        } label: {
          Label {
            Text(OnboardingScreenCopy.menuBarIconHidden)
          } icon: {
            Image(systemName: "exclamationmark.circle")
              .foregroundStyle(Theme.warning)
          }
        }
      }
    }
    ForEach(Array(permissions.enumerated()), id: \.element.kind) { index, row in
      Section {
        permissionRow(row)
      } header: {
        if index == 0 { tallyStrip }
      } footer: {
        if index == permissions.count - 1 {
          Text(OnboardingScreenCopy.rechecked)
        }
      }
    }
    Section {
      ForEach(settings, id: \.kind) { row in
        settingRow(row)
      }
    } footer: {
      Text(OnboardingScreenCopy.settingsFooter)
    }
    updateSection
  }

  @ViewBuilder private var updateSection: some View {
    Section {
      Toggle(OnboardingScreenCopy.updateAutomatically, isOn: automaticUpdates)
      if let version = updater.availableVersion {
        LabeledContent {
          Button(OnboardingScreenCopy.installUpdate) { updater.checkForUpdates() }
            .disabled(!updater.canCheck)
            .accessibilityIdentifier("updates.install")
        } label: {
          Text(OnboardingScreenCopy.updateAvailable(version))
            .accessibilityIdentifier("updates.available")
        }
      } else {
        LabeledContent {
          HStack {
            lastCheckedValue
            // On the button, not the Section: canCheckForUpdates is false for the
            // whole of a check, and false where the updater never started.
            Button(OnboardingScreenCopy.checkForUpdates) { updater.checkForUpdates() }
              .disabled(!updater.canCheck)
              .accessibilityIdentifier("updates.check")
          }
        } label: {
          Text(OnboardingScreenCopy.lastChecked)
        }
      }
    } footer: {
      Text(OnboardingScreenCopy.updatesFooter)
    }
  }

  private var automaticUpdates: Binding<Bool> {
    Binding(
      get: { updater.automaticallyChecks },
      set: { updater.setAutomaticallyChecks($0) })
  }

  @ViewBuilder private var lastCheckedValue: some View {
    if let checked = updater.lastSuccessfulCheck {
      if Calendar.current.isDate(checked, inSameDayAs: Date()) {
        Text(OnboardingScreenCopy.checkedToday)
      } else {
        Text(verbatim: checked.formatted(date: .abbreviated, time: .omitted))
      }
    } else {
      Text(OnboardingScreenCopy.neverChecked)
    }
  }

  private var tallyStrip: some View {
    HStack(spacing: 8) {
      HStack(spacing: 3) {
        ForEach(permissions, id: \.kind) { row in
          Capsule()
            .fill(row.status == .granted ? Color.green : Theme.warning)
            .frame(width: 20, height: 3)
        }
      }
      Text(OnboardingScreenCopy.granted)
        .textCase(.uppercase)
        .foregroundStyle(Theme.textMuted)
      Text(verbatim: tally)
        .foregroundStyle(grantedCount == permissions.count ? Color.green : Theme.warning)
      Spacer()
      Button {
        model.refresh()
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.borderless)
      .help(Text(OnboardingScreenCopy.checkAgain))
      .accessibilityLabel(Text(OnboardingScreenCopy.checkAgain))
    }
    .font(Theme.label)
    .tracking(1)
    .textCase(nil)
    .accessibilityIdentifier("permissions.tally")
  }

  private func permissionRow(_ row: OnboardingRow) -> some View {
    LabeledContent {
      if row.status == .granted {
        Text(OnboardingScreenCopy.granted)
          .textCase(.uppercase)
          .font(Theme.label)
          .tracking(1)
          .foregroundStyle(Theme.textMuted)
      } else {
        Button {
          model.act(on: row)
        } label: {
          Text(verbatim: row.actionTitle)
        }
      }
    } label: {
      Label {
        rowLabel(row)
      } icon: {
        Image(
          systemName: row.status == .granted
            ? "checkmark.circle.fill"
            : "exclamationmark.circle"
        )
        .foregroundStyle(row.status == .granted ? Color.green : Theme.warning)
      }
    }
  }

  private func settingRow(_ row: OnboardingRow) -> some View {
    LabeledContent {
      switch row.kind {
      case .autostart:
        Toggle(
          isOn: Binding(
            get: { row.status == .granted },
            set: { _ in model.act(on: row) })
        ) {
          EmptyView()
        }
        .labelsHidden()
        .toggleStyle(.switch)
        .tint(Theme.accent)
        .accessibilityLabel(Text(verbatim: row.title))
      default:
        if row.status == .granted {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(Color.green)
            .accessibilityLabel(Text(OnboardingScreenCopy.rowGranted(row.title)))
        } else {
          Button {
            model.act(on: row)
          } label: {
            Text(verbatim: row.actionTitle)
          }
        }
      }
    } label: {
      rowLabel(row)
    }
  }

  @ViewBuilder
  private func rowLabel(_ row: OnboardingRow) -> some View {
    if OnboardingModel.blockingKinds.contains(row.kind) {
      Text(verbatim: row.title)
        .accessibilityLabel(
          Text(
            row.status == .granted
              ? OnboardingScreenCopy.rowGranted(row.title)
              : OnboardingScreenCopy.rowNotGranted(row.title)))
    } else {
      Text(verbatim: row.title)
    }
    Text(verbatim: row.explanation)
    if let path = row.settingsPath {
      Text(verbatim: path).textSelection(.enabled)
    }
    if row.kind == .autostart, let error = LoginItem.lastError {
      Text(verbatim: error).foregroundStyle(.red)
    }
  }
}

struct PrivacyDefaultsView: View {
  @AppStorage(AppSettings.historyEnabledKey)
  private var historyEnabled = AppSettings.historyEnabledDefault
  var summary: HistorySummary?
  @State private var showingSource = false

  var body: some View {
    Section {
      Toggle(OnboardingScreenCopy.keepHistory, isOn: $historyEnabled)
        .tint(Theme.accent)
      if let summary { tiles(summary) }
    } footer: {
      Text(OnboardingScreenCopy.privacyFooter)
    }
  }

  private func tiles(_ summary: HistorySummary) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 14) {
        tile(summary.savedTyping, OnboardingScreenCopy.tileSavedTyping, source: true)
        Divider()
        tile(summary.characters, OnboardingScreenCopy.tileCharacters, source: false)
        Divider()
        tile(summary.averageWords, OnboardingScreenCopy.tileAverageWords, source: false)
        Divider()
        tile(summary.dictations, OnboardingScreenCopy.tileDictations, source: false)
      }
      VStack(spacing: 12) {
        HStack(alignment: .top, spacing: 14) {
          tile(summary.savedTyping, OnboardingScreenCopy.tileSavedTyping, source: true)
          Divider()
          tile(summary.characters, OnboardingScreenCopy.tileCharacters, source: false)
        }
        Divider()
        HStack(alignment: .top, spacing: 14) {
          tile(summary.averageWords, OnboardingScreenCopy.tileAverageWords, source: false)
          Divider()
          tile(summary.dictations, OnboardingScreenCopy.tileDictations, source: false)
        }
      }
    }
    .padding(.vertical, 4)
    .accessibilityIdentifier("history.summary")
  }

  private func tile(
    _ value: String, _ caption: LocalizedStringResource,
    source: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 5) {
        Text(verbatim: value)
          .font(.system(size: 19, weight: .semibold))
          .monospacedDigit()
        if source {
          Button {
            showingSource = true
          } label: {
            Image(systemName: "info.circle")
          }
          .buttonStyle(.borderless)
          .accessibilityLabel(Text(OnboardingScreenCopy.figureSource))
          .popover(isPresented: $showingSource, arrowEdge: .bottom) {
            typingSource
          }
        }
      }
      Text(caption)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(OnboardingScreenCopy.tileAccessibility(value, caption)))
  }

  private var typingSource: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(OnboardingScreenCopy.typingTitle).font(.headline)
      Text(
        OnboardingScreenCopy.typingRate(
          Int(TypingEffort.wordsPerMinute),
          Int(TypingEffort.charactersPerWord)))
      Text(OnboardingScreenCopy.typingStudy)
      Text(OnboardingScreenCopy.typingCaveat)
      Divider()
      Text(OnboardingScreenCopy.typingCounts)
    }
    .font(.callout)
    .foregroundStyle(.secondary)
    .frame(width: 330, alignment: .leading)
    .padding(16)
  }
}
