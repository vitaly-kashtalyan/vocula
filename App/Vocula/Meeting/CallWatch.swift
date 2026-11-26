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
  private var polling: Task<Void, Never>?

  init(meetings: Meetings) {
    self.meetings = meetings
  }

  func start() {
    if VoculaAppDelegate.isSecondCopy {
      if ProcessInfo.processInfo.arguments.contains("-VoculaPretendCall") {
        let safari = "/Applications/Safari.app"
        panel.show(
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
    guard UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true else { return }
    let clients = await Task.detached(priority: .utility) { Self.clients() }.value
    let recording = meetings.status.isRecording || meetings.status.busy
    let now = ProcessInfo.processInfo.systemUptime
    guard let pid = offer.observe(clients, at: now, recording: recording) else { return }
    let app = Self.app(of: pid)
    panel.show(app: app?.name, icon: app.map { NSWorkspace.shared.icon(forFile: $0.path) }) {
      [weak self] in
      guard let self, !self.meetings.status.busy else { return }
      _ = self.meetings.toggle()
    }
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

@MainActor
final class CallOfferPanel {
  static let shownFor: Duration = .seconds(20)

  private var panel: NSPanel?
  private var hiding: Task<Void, Never>?

  func show(app: String?, icon: NSImage?, record: @escaping () -> Void) {
    close()
    let host = FirstClickHostingView(
      rootView: CallOfferView(
        app: app,
        icon: icon,
        record: { [weak self] in
          self?.close()
          record()
        },
        dismiss: { [weak self] in self?.close() }))
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
    Announce.say(String(localized: MenuCopy.callOffer(in: app)))
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
  let app: String?
  let icon: NSImage?
  let record: () -> Void
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
          if let app {
            Text(verbatim: app)
              .font(.headline)
          }
          Text(MenuCopy.callOfferUnnamed)
            .foregroundStyle(app == nil ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      HStack(spacing: 8) {
        Spacer()
        Button(MenuCopy.callOfferNotNow, action: dismiss)
          .accessibilityIdentifier("callOffer.notNow")
        Button(action: record) {
          Label(MenuCopy.callOfferRecord, systemImage: "record.circle.fill")
        }
        .buttonStyle(RecordButtonStyle())
        .accessibilityIdentifier("callOffer.record")
      }
    }
    .padding(14)
    .frame(width: 340)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
  }

  @ViewBuilder
  private var source: some View {
    if let icon {
      Image(nsImage: icon)
        .resizable()
    } else {
      Image(systemName: "phone.fill")
        .font(.title2)
        .foregroundStyle(.secondary)
    }
  }
}

private struct RecordButtonStyle: ButtonStyle {
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
