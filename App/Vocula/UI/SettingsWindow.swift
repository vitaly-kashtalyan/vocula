import AppKit
import Combine
import SwiftUI
import VoculaKit

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
  case status, permissions, keyboard, languages, microphone, models, history, diagnostics,
    licence, appearance

  var id: Self { self }

  var title: LocalizedStringResource {
    switch self {
    case .status:
      return .init(
        "settings.section.status", defaultValue: "Status",
        comment: "Sidebar section: the dashboard.")
    case .permissions:
      return .init(
        "settings.section.permissions", defaultValue: "Permissions",
        comment: "Sidebar section: the three macOS grants.")
    case .keyboard:
      return .init(
        "settings.section.keyboard", defaultValue: "Keyboard",
        comment: "Sidebar section: the record key and the language key.")
    case .models:
      return .init(
        "settings.section.models", defaultValue: "Models",
        comment: "Sidebar section: the downloadable recognition models.")
    case .languages:
      return .init(
        "settings.section.languages", defaultValue: "Languages",
        comment: "Sidebar section: which languages are recognised.")
    case .microphone:
      return .init(
        "settings.section.microphone", defaultValue: "Microphone",
        comment:
          "Sidebar section: the ranked input devices; must match macOS's own Microphone pane name in the glossary."
      )
    case .history:
      return .init(
        "settings.section.history", defaultValue: "History",
        comment: "Sidebar section: past dictations.")
    case .diagnostics:
      return .init(
        "settings.section.diagnostics", defaultValue: "Diagnostics",
        comment: "Sidebar section: the diagnostic log.")
    case .licence:
      return .init(
        "settings.section.licence", defaultValue: "Licence",
        comment: "Sidebar section: trial state and licence key.")
    case .appearance:
      return .init(
        "settings.section.appearance", defaultValue: "Appearance",
        comment: "Sidebar section: light/dark tiles.")
    }
  }

  static let groups:
    [(
      id: String, title: LocalizedStringResource?,
      sections: [SettingsSection]
    )] = [
      ("top", nil, [.status, .permissions]),
      (
        "dictation",
        .init(
          "settings.group.dictation", defaultValue: "Dictation",
          comment: "Sidebar group heading, shown upper-cased."),
        [.keyboard, .languages, .microphone, .models]
      ),
      (
        "data",
        .init(
          "settings.group.data", defaultValue: "Data",
          comment: "Sidebar group heading, shown upper-cased."),
        [.history, .diagnostics]
      ),
      (
        "app",
        .init(
          "settings.group.app", defaultValue: "App",
          comment: "Sidebar group heading, shown upper-cased."),
        [.licence, .appearance]
      ),
    ]

  var systemImage: String {
    switch self {
    case .status: return "waveform"
    case .permissions: return "checkmark.shield"
    case .keyboard: return "keyboard"
    case .models: return "cpu"
    case .languages: return "globe"
    case .microphone: return "mic"
    case .history: return "clock.arrow.circlepath"
    case .diagnostics: return "stethoscope"
    case .licence: return "key"
    case .appearance: return "circle.lefthalf.filled"
    }
  }
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
  @Published var selection: SettingsSection? = .status
}

struct SettingsWindowView: View {
  @AppStorage("sidebar.railed") private var railed = false
  @ObservedObject var navigation: SettingsNavigationModel
  @ObservedObject var onboarding: OnboardingModelObservable
  let updater: UpdaterController
  let menu: MenuBarController
  let downloader: ModelDownloader
  let coordinator: AppCoordinator
  let historyModel: HistoryWindowModel
  let onModelsReady: () async -> Void

  @ViewBuilder
  private func sidebarRow(_ section: SettingsSection) -> some View {
    let ink: Color = section == navigation.selection ? Theme.onAccent : Theme.textPrimary
    Label {
      Text(section.title)
    } icon: {
      Image(systemName: section.systemImage)
    }
    .labelStyle(SidebarLabelStyle(compact: railed, ink: ink))
    .badge(section == .permissions ? incompletePermissionsCount : 0)
    .tag(section)
    .accessibilityIdentifier("sidebar.\(section.rawValue)")
    .help(railed ? Text(section.title) : Text(verbatim: ""))
  }

  var body: some View {
    NavigationSplitView {
      List(selection: $navigation.selection) {
        ForEach(SettingsSection.groups, id: \.id) { group in
          Section {
            ForEach(group.sections) { section in
              sidebarRow(section)
            }
          } header: {
            if let title = group.title, !railed {
              TokenLabel(text: title)
                .accessibilityIdentifier("sidebar.group.\(group.id)")
            }
          }
        }
      }
      .listStyle(.sidebar)
      .toolbar(removing: .sidebarToggle)
      .tint(Theme.accent)
      .safeAreaInset(edge: .top) { SidebarBrand(compact: railed) }
      .safeAreaInset(edge: .bottom) { versionBar }
      .contentMargins(.bottom, versionBarHeight, for: .scrollContent)
      .navigationSplitViewColumnWidth(
        min: railed ? railWidth : sidebarMinimumWidth,
        ideal: railed ? railWidth : 208,
        max: railed ? railWidth : 280)
    } detail: {
      Form { detail }
        .formStyle(.grouped)
        .accessibilityIdentifier(
          "detail.\((navigation.selection ?? .status).rawValue)"
        )
        .navigationTitle((navigation.selection ?? .status).title)
        .scrollContentBackground(.hidden)
        .background(Theme.windowBackground)
    }
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button {
          withAnimation(.easeInOut(duration: 0.18)) { railed.toggle() }
        } label: {
          Image(systemName: railed ? "sidebar.left" : "sidebar.leading")
        }
        .help(railed ? Text(SidebarCopy.showSectionNames) : Text(SidebarCopy.collapseToIcons))
      }
    }
    .tint(Theme.accentText)
    .frame(minWidth: minimumWindowWidth, minHeight: minimumWindowHeight)
    .refreshOnActivate {
      onboarding.refresh()
      coordinator.recheckAccessibility()
    }
  }

  private var versionBar: some View {
    Text(verbatim: Bundle.main.versionAndBuild)
      .font(Theme.readout)
      .foregroundStyle(Theme.textMuted)
      .frame(maxWidth: .infinity, minHeight: versionBarHeight)
      .opacity(railed ? 0 : 1)
  }

  private var incompletePermissionsCount: Int {
    OnboardingModel.incomplete(onboarding.rows).count
  }

  @ViewBuilder
  private var detail: some View {
    switch navigation.selection ?? .status {
    case .status:
      StatusSettingsView(
        onboarding: onboarding, menu: menu, coordinator: coordinator,
        downloader: downloader, historyModel: historyModel,
        openSection: { navigation.selection = $0 })
    case .microphone:
      MicrophoneSettingsView()
    case .diagnostics:
      DiagnosticsSettingsView(menu: menu, coordinator: coordinator)
    case .permissions:
      PermissionsSettingsSection(model: onboarding, updater: updater)
    case .models:
      ModelPickerView(downloader: downloader, onModelsReady: onModelsReady)
    case .languages:
      LanguagePickerView()
    case .keyboard:
      KeyboardSettingsSection(menu: menu, coordinator: coordinator)
    case .history:
      HistorySettingsSection(model: historyModel)
    case .licence:
      LicenceSettingsView()
    case .appearance:
      AppearanceSettingsView()
    }
  }
}

private struct KeyboardSettingsSection: View {
  @ObservedObject var menu: MenuBarController
  let coordinator: AppCoordinator

  private var alert: String? {
    switch menu.iconState {
    case .error(let reason): return menu.showsDownloadAction ? nil : reason
    case .keyLost(let reason): return reason
    default: return nil
    }
  }

  var body: some View {
    if let alert {
      Section {
        Label {
          Text(verbatim: alert)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.red)
      }
    }
    KeyboardSettingsContent(coordinator: coordinator)
  }
}

private struct HistorySettingsSection: View {
  @ObservedObject var model: HistoryWindowModel

  private var summary: HistorySummary? {
    let characters = model.days.reduce(0) { $0 + $1.insertedCharacters }
    guard characters > 0 else { return nil }
    return HistorySummary(
      savedTyping: duration(TypingEffort.typingSeconds(characters: characters)),
      characters: compact(characters),
      averageWords: model.averageWordsThisYear.map(compact) ?? "—",
      dictations: compact(model.days.reduce(0) { $0 + $1.count }))
  }

  private func compact(_ value: Int) -> String {
    value.formatted(.number.notation(.compactName).locale(.interface))
  }

  private func duration(_ seconds: Double) -> String {
    let allowed: Set<Duration.UnitsFormatStyle.Unit>
    switch seconds {
    case ..<60: allowed = [.seconds]
    case ..<3_600: allowed = [.minutes]
    case ..<86_400: allowed = [.hours, .minutes]
    default: allowed = [.days, .hours]
    }
    return Duration.seconds(max(0, seconds.rounded()))
      .formatted(.units(allowed: allowed, width: .narrow).locale(.interface))
  }

  var body: some View {
    PrivacyDefaultsView(summary: summary)
    HistoryView(model: model)
      .task { await model.reload() }
      .refreshOnActivate { Task { await model.reload() } }
  }
}

private struct SidebarBrand: View {
  let compact: Bool

  var body: some View {
    HStack(spacing: 9) {
      Image(nsImage: MenuBarMark.idle.image)
        .renderingMode(.template)
        .resizable()
        .frame(width: 30, height: 30)
        .foregroundStyle(Theme.brandRamp)
      if !compact {
        Text(verbatim: "Vocula")
          .font(.system(size: 19, weight: .bold, design: .rounded))
          .foregroundStyle(Theme.brandRamp)
          .fixedSize()
      }
    }
    .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
    .padding(.horizontal, compact ? 0 : 14)
    .padding(.top, 4)
    .padding(.bottom, 12)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: "Vocula"))
  }
}

private let railWidth: CGFloat = 78
private let versionBarHeight: CGFloat = 38

private let sidebarMinimumWidth: CGFloat = 190
private let formCardInset: CGFloat = 20
private let formRowInset: CGFloat = 16
private let mapBreathingRoom: CGFloat = 14

private let minimumWindowHeight: CGFloat = 620

private let minimumWindowWidth =
  sidebarMinimumWidth
  + formCardInset * 2
  + formRowInset * 2
  + HistoryMapGeometry.width
  + mapBreathingRoom

private struct SidebarLabelStyle: LabelStyle {
  let compact: Bool
  let ink: Color

  func makeBody(configuration: Configuration) -> some View {
    if compact {
      configuration.icon
        .font(.system(size: 17))
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .center)
    } else {
      HStack(spacing: 6) {
        configuration.icon
          .foregroundStyle(ink)
        configuration.title
          .foregroundStyle(ink)
      }
      .accessibilityElement(children: .combine)
    }
  }
}
