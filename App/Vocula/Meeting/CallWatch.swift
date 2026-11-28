import AppKit
import CoreAudio
import Darwin
import SwiftUI
import VoculaKit

@MainActor
final class CallWatch {
  static let enabledKey = "meeting.offersOnCall"

  private let meetings: Meetings
  private let panel = CallOfferPanel()
  private var offer = CallOffer()
  private var ending = CallEndOffer()
  private var polling: Task<Void, Never>?

  init(meetings: Meetings) {
    self.meetings = meetings
  }

  func start() {
    if VoculaAppDelegate.isSecondCopy {
      let arguments = ProcessInfo.processInfo.arguments
      if arguments.contains("-VoculaPretendQuiet") {
        panel.show(.quiet, app: nil, icon: nil) {}
      } else if arguments.contains("-VoculaPretendCall")
        || arguments.contains("-VoculaPretendCallEnd")
      {
        let safari = "/Applications/Safari.app"
        panel.show(
          arguments.contains("-VoculaPretendCallEnd") ? .end : .start,
          app: URL(fileURLWithPath: safari).deletingPathExtension().lastPathComponent,
          icon: NSWorkspace.shared.icon(
            forFile: URL(fileURLWithPath: safari).resolvingSymlinksInPath().path)
        ) {}
      }
      return
    }
    guard polling == nil else { return }
    polling = Task { [weak self] in
      while !Task.isCancelled {
        await self?.tick()
        try? await Task.sleep(for: .seconds(2))
      }
    }
  }

  private func tick() async {
    let enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    let clients = enabled ? await Task.detached(priority: .utility) { Self.clients() }.value : []
    let now = ProcessInfo.processInfo.systemUptime
    switch ending.observe(
      clients, at: now, recording: enabled && meetings.status.isRecording,
      quiet: meetings.status.isQuiet)
    {
    case .offer(let pid):
      show(.end, for: pid, decline: { [weak self] in self?.ending.answered() }) {
        [weak self] in self?.stopMeeting()
      }
    case .offerQuiet:
      panel.show(.quiet, app: nil, icon: nil, decline: { [weak self] in self?.ending.answered() }) {
        [weak self] in self?.stopMeeting()
      }
    case .withdraw:
      panel.close()
    case nil:
      break
    }
    let recording = meetings.status.isRecording || meetings.status.busy
    guard enabled, let pid = offer.observe(clients, at: now, recording: recording) else { return }
    show(.start, for: pid) { [weak self] in
      guard let self, !self.meetings.status.busy else { return }
      _ = self.meetings.toggle()
    }
  }

  private func stopMeeting() {
    ending.answered()
    guard meetings.status.isRecording else { return }
    _ = meetings.toggle()
  }

  private func show(
    _ kind: CallOfferKind, for pid: Int32, decline: @escaping () -> Void = {},
    accept: @escaping () -> Void
  ) {
    let app = Self.app(of: pid)
    panel.show(
      kind, app: app?.name, icon: app.map { NSWorkspace.shared.icon(forFile: $0.path) },
      decline: decline, accept: accept)
  }

  nonisolated static func clients() -> [AudioClient] {
    let own = getpid()
    return processObjects().compactMap { object in
      guard let pid = read(object, kAudioProcessPropertyPID).map({ Int32(bitPattern: $0) }),
        pid != own,
        let input = read(object, kAudioProcessPropertyIsRunningInput),
        let output = read(object, kAudioProcessPropertyIsRunningOutput)
      else { return nil }
      return AudioClient(pid: pid, input: input != 0, output: output != 0)
    }
  }

  private nonisolated static func processObjects() -> [AudioObjectID] {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0
    else { return [] }
    var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr
    else { return [] }
    return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
  }

  private nonisolated static func read(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector
  ) -> UInt32? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
      ? value : nil
  }

  private static func app(of pid: Int32) -> (name: String, path: String)? {
    var buffer = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    let path = String(
      decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    guard let app = CallOffer.appPath(ofExecutable: path) else { return nil }
    return (URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent, app)
  }
}

enum CallOfferKind {
  case start
  case end
  case quiet
}

@MainActor
final class CallOfferPanel {
  static let shownFor: Duration = .seconds(20)

  private var panel: NSPanel?
  private var hiding: Task<Void, Never>?

  func show(
    _ kind: CallOfferKind, app: String?, icon: NSImage?, decline: @escaping () -> Void = {},
    accept: @escaping () -> Void
  ) {
    close()
    let host = FirstClickHostingView(
      rootView: CallOfferView(
        kind: kind,
        app: app,
        icon: icon,
        accept: { [weak self] in
          self?.close()
          accept()
        },
        dismiss: { [weak self] in
          self?.close()
          decline()
        }))
    let size = host.fittingSize
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered, defer: false)
    panel.contentView = host
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    if let screen = NSScreen.main?.visibleFrame {
      panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - size.width - 12, y: screen.maxY - 12))
    }
    panel.orderFrontRegardless()
    self.panel = panel
    let spoken: [LocalizedStringResource] =
      switch kind {
      case .start: [MenuCopy.callOffer(in: app)]
      case .end: [MenuCopy.callEndOffer(in: app)]
      case .quiet: [MenuCopy.quietOfferTitle, MenuCopy.quietOffer]
      }
    Announce.say(spoken.map { String(localized: $0) }.joined(separator: "\n"))
    guard kind == .start else { return }
    hiding = Task { [weak self] in
      try? await Task.sleep(for: Self.shownFor)
      if !Task.isCancelled { self?.close() }
    }
  }

  func close() {
    hiding?.cancel()
    hiding = nil
    panel?.orderOut(nil)
    panel = nil
  }
}

private final class FirstClickHostingView: NSHostingView<CallOfferView> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct CallOfferView: View {
  let kind: CallOfferKind
  let app: String?
  let icon: NSImage?
  let accept: () -> Void
  let dismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 16, height: 16)
        Text(verbatim: ProcessInfo.processInfo.processName)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .accessibilityHidden(true)
      HStack(spacing: 12) {
        source
          .frame(width: 40, height: 40)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          if let title {
            title
              .font(.headline)
              .fixedSize(horizontal: false, vertical: true)
          }
          question
            .foregroundStyle(title == nil ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      HStack(spacing: 8) {
        Spacer()
        Button(
          kind == .start ? MenuCopy.callOfferNotNow : MenuCopy.callEndOfferKeep, action: dismiss
        )
        .accessibilityIdentifier(identifier + (kind == .start ? ".notNow" : ".keep"))
        Button(action: accept) {
          Label(
            kind == .start ? MenuCopy.callOfferRecord : MenuCopy.callEndOfferStop,
            systemImage: kind == .start ? "record.circle.fill" : "stop.circle.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityIdentifier(identifier + (kind == .start ? ".record" : ".stop"))
      }
    }
    .padding(14)
    .frame(width: 340)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
  }

  private var title: Text? {
    kind == .quiet ? Text(MenuCopy.quietOfferTitle) : app.map { Text(verbatim: $0) }
  }

  private var question: Text {
    switch kind {
    case .start: Text(MenuCopy.callOfferUnnamed)
    case .end: Text(MenuCopy.callEndOfferUnnamed)
    case .quiet: Text(MenuCopy.quietOffer)
    }
  }

  private var identifier: String {
    switch kind {
    case .start: "callOffer"
    case .end: "callEndOffer"
    case .quiet: "quietOffer"
    }
  }

  @ViewBuilder
  private var source: some View {
    if let icon {
      Image(nsImage: icon)
        .resizable()
    } else {
      Image(systemName: kind == .quiet ? "waveform.slash" : "phone.fill")
        .font(.title2)
        .foregroundStyle(.secondary)
    }
  }
}

private struct PrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .foregroundStyle(Theme.onAccent)
      .padding(.horizontal, 12)
      .padding(.vertical, 5)
      .background(
        Theme.accentFill.opacity(configuration.isPressed ? 0.75 : 1),
        in: RoundedRectangle(cornerRadius: Theme.Radius.control))
  }
}
