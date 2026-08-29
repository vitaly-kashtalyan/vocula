import SwiftUI
import VoculaKit

struct AppearanceSettingsView: View {
  @AppStorage(AppearancePreference.storageKey)
  private var stored = AppearancePreference.default.rawValue

  private var selection: AppearancePreference { AppearancePreference(stored: stored) }

  @State private var languageCode = InterfaceLanguages.selected(
    stored: UserDefaults.standard.stringArray(forKey: InterfaceLanguages.defaultsKey),
    available: AppearanceSettingsView.available.map(\.code))

  var body: some View {
    Section {
      HStack(alignment: .top, spacing: 18) {
        ForEach(AppearancePreference.allCases, id: \.rawValue) { choice in
          AppearanceTile(preference: choice, isSelected: selection == choice) {
            stored = choice.rawValue
            choice.apply()
          }
        }
        Spacer(minLength: 0)
      }
      .padding(.vertical, 6)
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        Text(AppearanceScreenCopy.noSettingNeeded)
        Text(AppearanceScreenCopy.stripKeepsItsGrey)
      }
    }

    language
  }

  @ViewBuilder
  private var language: some View {
    Section {
      Picker(selection: $languageCode) {
        Text(AppearanceScreenCopy.matchSystem)
          .tag(InterfaceLanguages.systemCode)
        Divider()
        ForEach(Self.available) { language in
          Text(verbatim: language.name).tag(language.code)
        }
      } label: {
        Text(AppearanceScreenCopy.interfaceLanguage)
      }
      .accessibilityIdentifier("appearance.language")
      .onChange(of: languageCode) { _, code in
        let defaults = UserDefaults.standard
        if let override = InterfaceLanguages.override(for: code) {
          defaults.set(override, forKey: InterfaceLanguages.defaultsKey)
        } else {
          defaults.removeObject(forKey: InterfaceLanguages.defaultsKey)
        }
      }

      if needsRelaunch {
        Button(AppearanceScreenCopy.relaunchNow) { Relaunch.now(reopening: .appearance) }
          .accessibilityIdentifier("appearance.language.relaunch")
      }
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        Text(AppearanceScreenCopy.interfaceLanguageExplained)
        if needsRelaunch { Text(AppearanceScreenCopy.relaunchNeeded) }
      }
    }
  }

  private static let available = InterfaceLanguages.available(
    in: Bundle.main.localizations)

  private var needsRelaunch: Bool {
    languageCode != LaunchInterfaceLanguage.code
  }
}

private struct AppearanceTile: View {
  let preference: AppearancePreference
  let isSelected: Bool
  let choose: () -> Void

  private static let size = CGSize(width: 124, height: 78)

  var body: some View {
    Button(action: choose) {
      VStack(spacing: 8) {
        miniature
          .frame(width: Self.size.width, height: Self.size.height)
          .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
          }
          .overlay {
            RoundedRectangle(cornerRadius: 9.5, style: .continuous)
              .inset(by: -2.5)
              .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2.5)
          }
        Text(preference.title)
          .font(.system(size: 11))
          .foregroundStyle(isSelected ? Theme.accentText : Theme.textSecondary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("appearance.\(preference.rawValue)")
    .accessibilityLabel(preference.title)
    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
  }

  @ViewBuilder
  private var miniature: some View {
    switch preference {
    case .light: WindowMiniature(skin: .light)
    case .dark: WindowMiniature(skin: .dark)
    case .system:
      WindowMiniature(skin: .light)
        .overlay {
          WindowMiniature(skin: .dark)
            .mask {
              HStack(spacing: 0) {
                Color.clear
                Color.black
              }
            }
        }
    }
  }
}

private struct WindowMiniature: View {
  struct Skin {
    let desktop: (Color, Color)
    let window: Color, card: Color, sidebar: Color, line: Color, accent: Color

    static let light = Skin(
      desktop: (Color(hex: 0xB9AE9C), Color(hex: 0x8D8271)),
      window: Color(hex: Theme.Ink.windowLight),
      card: Color(hex: Theme.Ink.cardLight),
      sidebar: Color(hex: 0xE8E5E1), line: Color(hex: 0xC3BFB9),
      accent: Color(hex: Theme.Ink.fillLight))
    static let dark = Skin(
      desktop: (Color(hex: 0x38322A), Color(hex: 0x15130F)),
      window: Color(hex: Theme.Ink.windowDark),
      card: Color(hex: Theme.Ink.cardDark),
      sidebar: Color(hex: 0x242426), line: Color(hex: 0x55555A),
      accent: Color(hex: Theme.Ink.fillDark))
  }

  let skin: Skin

  var body: some View {
    LinearGradient(
      colors: [skin.desktop.0, skin.desktop.1],
      startPoint: .topLeading, endPoint: .bottomTrailing
    )
    .overlay {
      window
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 2.5, y: 1.5)
        .padding(10)
    }
  }

  private var window: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        bar(width: 22, color: skin.accent)
        bar(width: 18, color: skin.line)
        bar(width: 21, color: skin.line)
        Spacer(minLength: 0)
      }
      .padding(6)
      .frame(width: 34, alignment: .leading)
      .frame(maxHeight: .infinity)
      .background(skin.sidebar)

      VStack(alignment: .leading, spacing: 4) {
        RoundedRectangle(cornerRadius: 2.5)
          .fill(skin.card)
          .frame(height: 19)
          .overlay(alignment: .leading) {
            VStack(alignment: .leading, spacing: 3.5) {
              bar(width: 28, color: skin.line)
              bar(width: 18, color: skin.line)
            }
            .padding(.leading, 5)
          }
        RoundedRectangle(cornerRadius: 2.5)
          .fill(skin.card)
          .frame(height: 12)
        Spacer(minLength: 0)
      }
      .padding(6)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(skin.window)
    }
  }

  private func bar(width: CGFloat, color: Color) -> some View {
    Capsule().fill(color).frame(width: width, height: 2.5)
  }
}
