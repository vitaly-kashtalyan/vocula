import AppKit
import SwiftUI
import VoculaKit

private let contentHeight: CGFloat = 22

@MainActor
final class IndicatorPanel {
  private let panel: NSPanel
  private let model = IndicatorModel()
  private var noteDismissal: Task<Void, Never>?

  private static let height = contentHeight + 10
  private static let refusalHeight: CGFloat = 40
  private static let refusalWidth: CGFloat = 260
  private static let maxChipWidth: CGFloat = 460
  static let maxChipLines = 3
  private static let width: CGFloat = 180
  private static let bottomGap: CGFloat = 1

  init() {
    panel = NSPanel(
      contentRect: NSRect(
        x: 0, y: 0,
        width: Self.width, height: Self.height),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered, defer: false)
    panel.isFloatingPanel = true
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.hidesOnDeactivate = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    // A click here takes key focus off the target, and TargetGuard then refuses the insert.
    panel.ignoresMouseEvents = true
    panel.contentView = NSHostingView(rootView: IndicatorView(model: model))

    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.position() }
    }
  }

  func show(_ status: ControllerStatus) {
    switch indicatorAction(for: status) {
    case .ignore:
      return
    case .display(let displayStatus):
      if supersedesNote(displayStatus) {
        noteDismissal?.cancel()
        noteDismissal = nil
        model.note = nil
      }
      model.status = displayStatus
      position()
      if !panel.isVisible { panel.orderFrontRegardless() }
      if case .refused(let reason, _) = displayStatus { Announce.say(reason) }
    }
  }

  func showStatus(_ text: String) {
    if model.status_ != text { Announce.say(text) }
    model.status_ = text
    model.noteIsAlert = false
    position()
    if !panel.isVisible { panel.orderFrontRegardless() }
  }

  func clearStatus() {
    guard model.status_ != nil else { return }
    model.status_ = nil
    position()
  }

  func note(
    _ text: String, for duration: Duration = .milliseconds(1_200),
    alert: Bool = false
  ) {
    let wasVisible = panel.isVisible
    Announce.say(text)
    model.note = text
    model.noteIsAlert = alert
    position()
    if !wasVisible { panel.orderFrontRegardless() }

    noteDismissal?.cancel()
    noteDismissal = Task { [weak self] in
      do { try await Task.sleep(for: duration) } catch { return }
      await MainActor.run {
        guard let self else { return }
        self.model.note = nil
        self.position()
        if !wasVisible { self.panel.orderOut(nil) }
      }
    }
  }

  func hide() {
    model.status = .idle
    noteDismissal?.cancel()
    noteDismissal = nil
    model.note = nil
    panel.orderOut(nil)
  }

  static func chipSize(for text: String, on screen: NSRect) -> (CGFloat, CGFloat) {
    let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let furniture: CGFloat = 14 + 8 + 9 * 2
    let cap = min(screen.width / 2, Self.maxChipWidth)
    let oneLine = (text as NSString).size(withAttributes: attributes).width.rounded(.up)
    if oneLine + furniture <= cap {
      return (max(Self.refusalWidth, oneLine + furniture), Self.refusalHeight)
    }
    let lines = min(Self.maxChipLines, Self.naturalLines(for: text, on: screen))
    let box = NSSize(width: cap - furniture, height: .greatestFiniteMagnitude)
    return (cap, Self.refusalHeight + CGFloat(lines - 1) * Self.lineHeight(box, attributes))
  }

  static func naturalLines(for text: String, on screen: NSRect) -> Int {
    let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let furniture: CGFloat = 14 + 8 + 9 * 2
    let cap = min(screen.width / 2, Self.maxChipWidth)
    let box = NSSize(width: cap - furniture, height: .greatestFiniteMagnitude)
    let measured = (text as NSString).boundingRect(
      with: box, options: Self.textMeasuring, attributes: attributes)
    return max(1, Int((measured.height / Self.lineHeight(box, attributes)).rounded(.up)))
  }

  private static let textMeasuring: NSString.DrawingOptions = [
    .usesLineFragmentOrigin, .usesFontLeading,
  ]

  // boundingRect's own line, never the font metric: they differ by a twentieth
  // of a point, which rounds every one-line string up to two.
  private static func lineHeight(
    _ box: NSSize, _ attributes: [NSAttributedString.Key: Any]
  ) -> CGFloat {
    ("M" as NSString).boundingRect(
      with: box, options: Self.textMeasuring, attributes: attributes
    ).height
  }

  private func position() {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
    let frame = screen.visibleFrame
    let width: CGFloat
    let height: CGFloat
    if let chip = model.chip {
      (width, height) = Self.chipSize(for: chip.text, on: frame)
    } else {
      width = Self.width
      height = Self.height
    }
    let rect = NSRect(
      x: frame.midX - width / 2,
      y: frame.minY + Self.bottomGap,
      width: width, height: height)
    guard rect != panel.frame else { return }
    panel.setFrame(rect, display: true)
  }
}

@MainActor
private final class IndicatorModel: ObservableObject {
  @Published var status: ControllerStatus = .idle {
    didSet {
      recordLevel(of: status)
      updateTicker(for: status)
    }
  }
  @Published var note: String?
  @Published var status_: String?
  @Published var noteIsAlert = false
  @Published var levels: [CGFloat] = []
  private static let historyLength = WaveformGeometry.barCount

  @Published var phase: Double = 0
  private var ticker: Task<Void, Never>?
  private var tickerSpeed: Double = 0

  var chip: (icon: String, orange: Bool, text: String)? {
    if let status_ { return ("globe", false, status_) }
    if let note {
      return noteIsAlert
        ? ("exclamationmark.triangle", true, note)
        : ("globe", false, note)
    }
    if case .refused(let reason, _) = status {
      return ("exclamationmark.triangle", true, reason)
    }
    return nil
  }

  private func recordLevel(of status: ControllerStatus) {
    guard case .listening(let level) = status else {
      if !levels.isEmpty { levels = [] }
      return
    }
    levels.append(CGFloat(PCMSamples.displayLevel(level)))
    if levels.count > Self.historyLength {
      levels.removeFirst(levels.count - Self.historyLength)
    }
  }

  private func updateTicker(for status: ControllerStatus) {
    let speed: Double
    switch status {
    case .raising: speed = 4.0
    case .working: speed = 2.6
    default:
      ticker?.cancel()
      ticker = nil
      tickerSpeed = 0
      return
    }
    guard tickerSpeed != speed else { return }
    ticker?.cancel()
    tickerSpeed = speed
    ticker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(33))
        guard let self, !Task.isCancelled else { return }
        self.phase += speed * 0.033
      }
    }
  }
}

private struct IndicatorView: View {
  @ObservedObject var model: IndicatorModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)
      content
        .padding(.bottom, 5)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private var content: some View {
    if let content = model.chip {
      chip {
        Image(systemName: content.icon)
          .foregroundStyle(
            content.orange
              ? AnyShapeStyle(.orange)
              : AnyShapeStyle(Theme.paneRamp))
        Text(verbatim: content.text).lineLimit(IndicatorPanel.maxChipLines)
      }
    } else {
      waveform
    }
  }

  private var waveform: some View {
    let style = WaveformStyle(
      status: model.status,
      levels: model.levels,
      phase: model.phase)
    return Waveform(
      samples: style.samples, width: style.width,
      height: contentHeight,
      opacity: style.opacity, spread: style.spread,
      glass: Double(style.spread), palette: .pane
    )
    .animation(growth, value: style.width)
    .animation(growth, value: style.spread)
  }

  private var growth: Animation? {
    reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.95)
  }

  @ViewBuilder
  private func chip<Content: View>(@ViewBuilder _ body: () -> Content) -> some View {
    HStack(spacing: 8, content: body)
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(Theme.paneRamp)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .indicatorPane(.capsule)
  }
}

private struct WaveformStyle {
  var samples: [CGFloat] = []
  var width: CGFloat
  var opacity: Double
  var spread: CGFloat

  init(status: ControllerStatus, levels: [CGFloat], phase: Double) {
    switch status {
    case .idle, .finished, .refused:
      self.init(width: 34, opacity: 0.45, spread: 0)
    case .raising:
      self.init(
        samples: Self.bump(phase: phase, height: 0.35),
        width: WaveformGeometry.width, opacity: 0.55, spread: 1)
    case .working:
      self.init(
        samples: Self.bump(phase: phase, height: 0.5),
        width: WaveformGeometry.width, opacity: 0.7, spread: 1)
    case .listening:
      self.init(samples: levels, width: WaveformGeometry.width, opacity: 1, spread: 1)
    }
  }

  private init(
    samples: [CGFloat] = [], width: CGFloat,
    opacity: Double, spread: CGFloat
  ) {
    self.samples = samples
    self.width = width
    self.opacity = opacity
    self.spread = spread
  }

  private static func bump(phase: Double, height: CGFloat) -> [CGFloat] {
    (0..<WaveformGeometry.barCount).map { index in
      0.06 + height * CGFloat(max(0, sin(Double(index) * 0.22 - phase)))
    }
  }
}
