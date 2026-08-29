import AppKit
import SwiftUI
import VoculaKit

enum Theme {
  enum Ink {
    static let windowLight = Tokens.windowBgLight, windowDark = Tokens.windowBgDark
    static let cardLight = Tokens.cardBgLight, cardDark = Tokens.cardBgDark

    static let fillLight = Tokens.accentFillLight, fillDark = Tokens.accentFillDark
    static let inkLight = Tokens.accentInkLight, inkDark = Tokens.accentInkDark
    static let onAccentLight = Tokens.accentOnLight, onAccentDark = Tokens.accentOnDark

    static let markHot = Tokens.markHot

    static let warningLight = Tokens.warningTextLight
    static let warningDark = Tokens.warningTextDark
    static let warningBackingLight = Tokens.warningBackingLight
    static let warningBorderLight = Tokens.warningBorderLight
  }

  static let windowBackground = dynamic(light: Ink.windowLight, dark: Ink.windowDark)
  static let cardBackground = dynamic(light: Ink.cardLight, dark: Ink.cardDark)
  static let cardBorder = dynamic(
    light: 0x000000, lightAlpha: 0.08,
    dark: 0xFFFFFF, darkAlpha: 0.06)

  static let textPrimary = dynamic(
    light: Tokens.textPrimaryLight,
    dark: Tokens.textPrimaryDark)
  static let textSecondary = dynamic(
    light: Tokens.textSecondaryLight,
    dark: Tokens.textSecondaryDark)
  static let textMuted = dynamic(
    light: Tokens.textMutedLight,
    dark: Tokens.textMutedDark)

  static let accent = Color.accentColor
  static let accentText = dynamic(light: Ink.inkLight, dark: Ink.inkDark)

  static let onAccent = dynamic(light: Ink.onAccentLight, dark: Ink.onAccentDark)

  static func heatAlpha(_ level: Int) -> Double {
    let steps = [0, 0.18, 0.38, 0.64, 1.0]
    return steps[min(max(level, 0), steps.count - 1)]
  }

  static let warning = dynamic(light: Ink.warningLight, dark: Ink.warningDark)
  static let warningBackground = dynamic(
    light: Ink.warningBackingLight, lightAlpha: 1,
    dark: Ink.warningDark, darkAlpha: 0.08)
  static let warningBorder = dynamic(
    light: Ink.warningBorderLight, lightAlpha: 1,
    dark: Ink.warningDark, darkAlpha: 0.32)

  static let keycapFace = dynamic(
    light: 0xFFFFFF, lightAlpha: 1,
    dark: 0xFFFFFF, darkAlpha: 0.07)
  static let keycapEdge = dynamic(
    light: 0x000000, lightAlpha: 0.18,
    dark: 0xFFFFFF, darkAlpha: 0.14)
  static let keycapGloss = LinearGradient(
    colors: [
      Color.white.opacity(0.5),
      Color.white.opacity(0),
    ],
    startPoint: .top, endPoint: .bottom)
  static let keycapDrop = dynamic(
    light: 0x000000, lightAlpha: 0.12,
    dark: 0x000000, darkAlpha: 0.5)

  static let tileFill = dynamic(
    light: Ink.fillLight, lightAlpha: 0.18,
    dark: Ink.fillDark, darkAlpha: 0.16)

  enum Radius {
    static let control: CGFloat = 6
    static let card: CGFloat = 10
  }

  static let label = Font.system(size: 10, weight: .semibold, design: .monospaced)
  static let readout = Font.system(size: 11, design: .monospaced)
  static let keycap = Font.system(size: 14, weight: .medium, design: .monospaced)
  static let cardValue = Font.system(size: 14)
  static let heroLine = Font.system(size: 16)

  private static func dynamic(
    light: UInt32, lightAlpha: Double = 1,
    dark: UInt32, darkAlpha: Double = 1
  ) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(
          hex: isDark ? dark : light,
          alpha: isDark ? darkAlpha : lightAlpha)
      })
  }

  static let paneFill = LinearGradient(
    colors: [Color(white: 0.16).opacity(0.88), Color.black.opacity(0.88)],
    startPoint: .top, endPoint: .bottom)

  static let paneInk = Color(hex: Tokens.paneResting)
  static let paneHighlight = Color(hex: Tokens.markCool)
  static let paneSand = Color(hex: Ink.markHot)
  static let paneRamp = LinearGradient(
    colors: [paneHighlight, paneSand],
    startPoint: .leading, endPoint: .trailing)

  static let brandRamp = LinearGradient(
    colors: [
      dynamic(light: Tokens.textPrimaryLight, dark: Tokens.markCool),
      dynamic(light: Tokens.textPrimaryLight, dark: Tokens.markHot),
    ],
    startPoint: .leading, endPoint: .trailing)

  static let windowRampCool = dynamic(
    light: Tokens.textSecondaryLight,
    dark: Tokens.textPrimaryDark)
  static let windowRampWarm = dynamic(light: Ink.inkLight, dark: Ink.fillDark)
  static let windowRamp = LinearGradient(
    colors: [windowRampCool, windowRampWarm],
    startPoint: .leading, endPoint: .trailing)
}

extension Color {
  init(hex: UInt32) {
    self.init(nsColor: NSColor(hex: hex, alpha: 1))
  }
}

extension NSColor {
  convenience init(hex: UInt32, alpha: Double) {
    self.init(
      srgbRed: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      alpha: alpha)
  }
}

struct TokenLabel: View {
  let text: LocalizedStringResource

  var body: some View {
    Text(text)
      .textCase(.uppercase)
      .font(Theme.label)
      .tracking(1)
      .foregroundStyle(Theme.textMuted)
  }
}

extension View {
  func cardSurface(
    _ fill: Color, border: Color = Theme.cardBorder,
    lineWidth: CGFloat = 0.5
  ) -> some View {
    background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
      .overlay(
        RoundedRectangle(cornerRadius: Theme.Radius.card)
          .strokeBorder(border, lineWidth: lineWidth))
  }

  func refreshOnActivate(_ refresh: @escaping () -> Void) -> some View {
    onReceive(
      NotificationCenter.default.publisher(
        for: NSApplication.didBecomeActiveNotification)
    ) { _ in refresh() }
  }

  func dashboardRow() -> some View {
    listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
  }
}

struct SelectableRow<Label: View>: View {
  let isSelected: Bool
  let choose: () -> Void
  @ViewBuilder let label: () -> Label

  var body: some View {
    Button(action: choose) {
      LabeledContent {
        Image(systemName: "checkmark")
          .foregroundStyle(Theme.accent)
          .opacity(isSelected ? 1 : 0)
      } label: {
        label()
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
  }
}

struct StatusCard: View {
  let label: LocalizedStringResource
  let value: String
  let detail: String
  var detailIsAccented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      TokenLabel(text: label)
      Text(verbatim: value)
        .font(Theme.cardValue)
        .foregroundStyle(Theme.textPrimary)
        .lineLimit(2)
      Text(verbatim: detail)
        .font(Theme.readout)
        .foregroundStyle(detailIsAccented ? Theme.accentText : Theme.textMuted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .cardSurface(Theme.cardBackground)
  }
}

struct KeycapView: View {
  let name: String
  var accented = false

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Theme.Radius.control + 1)
  }

  var body: some View {
    Text(verbatim: name)
      .font(Theme.keycap)
      .foregroundStyle(accented ? Theme.onAccent : Theme.textPrimary)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .frame(minWidth: 30)
      .background {
        shape.fill(accented ? Theme.accent : Theme.keycapFace)
          .overlay(shape.fill(Theme.keycapGloss))
          .overlay(shape.strokeBorder(Theme.keycapEdge, lineWidth: 0.5))
          .shadow(color: Theme.keycapDrop, radius: 0, y: 1.5)
      }
  }
}

struct KeycapChord: View {
  let parts: [String]

  var body: some View {
    HStack(spacing: 5) {
      ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
        if index > 0 {
          Text(verbatim: "+")
            .font(.system(size: 11))
            .foregroundStyle(Theme.textMuted)
        }
        KeycapView(name: part)
      }
    }
  }
}

extension AppearancePreference {
  var nsAppearance: NSAppearance? {
    switch self {
    case .system: return nil
    case .light: return NSAppearance(named: .aqua)
    case .dark: return NSAppearance(named: .darkAqua)
    }
  }

  @MainActor
  func apply() { NSApp.appearance = nsAppearance }
}

extension View {
  func indicatorPane(
    _ shape: some Shape, horizontal: CGFloat = 0,
    vertical: CGFloat = 0, opacity: Double = 1
  ) -> some View {
    background {
      shape.fill(Theme.paneFill)
        .padding(.horizontal, -horizontal)
        .padding(.vertical, -vertical)
        .opacity(opacity)
        .transaction { $0.animation = nil }
    }
  }
}
