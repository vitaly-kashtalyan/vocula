import AppKit
import CoreAudio
import SwiftUI
import UniformTypeIdentifiers
import VoculaKit

struct MicrophoneSettingsView: View {
  @State private var priority = AppSettings().microphonePriority
  @State private var connected: [AudioInputDevice] = []
  @State private var inputVolumes: [String: Float] = [:]
  @State private var levels: [CGFloat] = []
  @State private var hovered: String?
  @State private var dropTarget: String?
  @State private var askedUID: String?
  @State private var meterFailed = false
  @State private var appIsActive = true
  @State private var scanGeneration = 0
  @State private var monitor = InputLevelMonitor()

  static let recommendedInputVolume: Float = 0.8
  private static let quietEnoughToExplain: Float = 0.6

  var body: some View {
    Section {
      ForEach(Array(priority.devices.enumerated()), id: \.element.uid) { index, device in
        row(device, index: index)
      }
    } header: {
      Text(MicrophoneScreenCopy.header)
    } footer: {
      VStack(alignment: .leading, spacing: 5) {
        Text(MicrophoneScreenCopy.fallbackRule)
        Text(MicrophoneScreenCopy.volumeIsShared)
      }
      .foregroundStyle(Theme.textSecondary)
    }
    .task { await refresh() }
    .refreshOnActivate {
      appIsActive = true
      Task { await refresh() }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: NSApplication.didResignActiveNotification)
    ) { _ in appIsActive = false }
    .task(id: listeningTarget) { await meter() }
    .onDisappear { Task { await monitor.stop() } }
  }

  private func row(_ device: RankedInputDevice, index: Int) -> some View {
    let live = connected.first { $0.uid == device.uid }
    let isActive = device.uid == activeUID
    return LabeledContent {
      reorder(device.uid, index: index)
    } label: {
      HStack(alignment: .top, spacing: 11) {
        Text(verbatim: String(index + 1))
          .font(Theme.readout)
          .monospacedDigit()
          .foregroundStyle(Theme.textMuted)
          .frame(width: 13, alignment: .trailing)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 7) {
          HStack(spacing: 10) {
            Text(verbatim: device.displayName)
              .frame(maxWidth: .infinity, alignment: .leading)
            if live == nil {
              Text(MicrophoneScreenCopy.notConnected)
                .font(Theme.readout)
                .foregroundStyle(Theme.textMuted)
            }
            if isActive { listeningReadout(live) }
          }
          if live?.isBluetooth == true {
            Text(MicrophoneScreenCopy.bluetoothProfile)
              .font(Theme.readout)
              .foregroundStyle(Theme.textSecondary)
          }
          if isActive { volume(device.uid) }
        }
      }
      .opacity(live == nil ? 0.5 : 1)
      .padding(.leading, 11)
      .overlay(alignment: .leading) {
        if isActive {
          RoundedRectangle(cornerRadius: 1.5)
            .fill(Theme.accent)
            .frame(width: 3)
        }
      }
      .background(
        Theme.accent.opacity(dropTarget == device.uid ? 0.16 : 0),
        in: RoundedRectangle(cornerRadius: Theme.Radius.control))
    }
    .onHover { hovered = $0 ? device.uid : (hovered == device.uid ? nil : hovered) }
    .onDrop(of: [.text], isTargeted: dropHighlight(device.uid)) { providers in
      receive(providers, at: index)
    }
  }

  private func dropHighlight(_ uid: String) -> Binding<Bool> {
    Binding(
      get: { dropTarget == uid },
      set: { dropTarget = $0 ? uid : (dropTarget == uid ? nil : dropTarget) })
  }

  private func receive(_ providers: [NSItemProvider], at index: Int) -> Bool {
    guard let provider = providers.first,
      provider.canLoadObject(ofClass: NSString.self)
    else { return false }
    _ = provider.loadObject(ofClass: NSString.self) { value, _ in
      guard let dragged = value as? String else { return }
      Task { @MainActor in
        guard priority.devices.contains(where: { $0.uid == dragged }) else { return }
        apply(priority.moved(uid: dragged, to: index))
      }
    }
    return true
  }

  private func reorder(_ uid: String, index: Int) -> some View {
    HStack(spacing: 6) {
      Button(MicrophoneScreenCopy.moveUp(name(uid)), systemImage: "chevron.up") {
        move(uid, by: -1)
      }
      .disabled(index == 0)
      Button(MicrophoneScreenCopy.moveDown(name(uid)), systemImage: "chevron.down") {
        move(uid, by: 1)
      }
      .disabled(index == priority.devices.count - 1)
      Image(systemName: "line.3.horizontal")
        .font(.system(size: 11, weight: .medium))
        .frame(width: 16, height: 18)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
        .onDrag { NSItemProvider(object: uid as NSString) }
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.borderless)
    .foregroundStyle(Theme.textMuted)
    .opacity(hovered == uid ? 1 : 0.45)
  }

  @ViewBuilder
  private func listeningReadout(_ device: AudioInputDevice?) -> some View {
    HStack(spacing: 10) {
      if listeningTarget != nil, !meterFailed {
        Waveform(
          samples: levels, width: WaveformGeometry.width, height: 18,
          opacity: 1, spread: 1, glass: 0, palette: .window
        )
        .accessibilityHidden(true)
      } else if let device, device.opensOnDemandOnly {
        Button {
          askedUID = askedUID == device.uid ? nil : device.uid
        } label: {
          if askedUID == device.uid {
            Text(MicrophoneScreenCopy.stop)
          } else {
            Text(MicrophoneScreenCopy.test)
          }
        }
        .buttonStyle(.borderless)
        .font(Theme.readout)
      }
      Text(MicrophoneScreenCopy.inUse)
        .font(Theme.label)
        .tracking(0.7)
        .foregroundStyle(Theme.onAccent)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5))
    }
  }

  @ViewBuilder
  private func volume(_ uid: String) -> some View {
    if inputVolumes[uid] != nil {
      LabeledContent(MicrophoneScreenCopy.inputVolume) {
        HStack(spacing: 10) {
          Slider(value: activeVolume, in: 0...1)
            .frame(minWidth: 160)
          Text(verbatim: volumePercentage(for: uid))
            .font(Theme.readout)
            .monospacedDigit()
            .foregroundStyle(isQuiet(uid) ? Theme.warning : Theme.textSecondary)
        }
      }
      if isVeryQuiet(uid) {
        Text(MicrophoneScreenCopy.veryQuiet(Int(Self.recommendedInputVolume * 100)))
          .font(Theme.readout)
          .foregroundStyle(Theme.warning)
      }
    } else {
      Text(MicrophoneScreenCopy.noVolumeControl)
        .font(Theme.readout)
        .foregroundStyle(Theme.textSecondary)
    }
    if meterFailed {
      Text(MicrophoneScreenCopy.couldNotOpen)
        .font(Theme.readout)
        .foregroundStyle(Theme.warning)
    }
    if connected.first(where: { $0.uid == uid })?.opensOnDemandOnly == true {
      Group {
        if askedUID == uid {
          Text(MicrophoneScreenCopy.listening)
        } else {
          Text(MicrophoneScreenCopy.notListening)
        }
      }
      .font(Theme.readout)
      .foregroundStyle(Theme.textSecondary)
    }
  }

  private var activeVolume: Binding<Double> {
    Binding(
      get: {
        guard let uid = activeUID, let volume = inputVolumes[uid] else { return 0 }
        return Double(volume)
      },
      set: { value in
        guard let uid = activeUID,
          let id = connected.first(where: { $0.uid == uid })?.id
        else { return }
        guard AudioInputDevices.setInputVolume(id, Float(value)) else { return }
        inputVolumes[uid] = AudioInputDevices.inputVolume(id) ?? Float(value)
      })
  }

  private var activeUID: String? {
    priority.firstAvailable(in: Set(connected.map(\.uid)))?.uid
  }

  private var listeningTarget: String? {
    guard let uid = activeUID, let device = connected.first(where: { $0.uid == uid })
    else { return nil }
    let request = InputMeterRequest(
      opensOnDemandOnly: device.opensOnDemandOnly,
      appIsActive: appIsActive,
      userAskedToListen: askedUID == uid)
    return InputMeterPolicy.shouldListen(request) ? uid : nil
  }

  private func meter() async {
    levels = []
    meterFailed = false
    guard let uid = listeningTarget,
      let device = connected.first(where: { $0.uid == uid })
    else { return await monitor.stop() }
    let opened = await monitor.listen(to: device.id)
    guard !Task.isCancelled else { return await monitor.stop() }
    meterFailed = !opened
    guard opened else { return }
    for await level in monitor.levelUpdates() {
      levels.append(CGFloat(PCMSamples.displayLevel(level)))
      if levels.count > WaveformGeometry.barCount {
        levels.removeFirst(levels.count - WaveformGeometry.barCount)
      }
    }
  }

  private func name(_ uid: String) -> String {
    priority.devices.first { $0.uid == uid }?.name ?? uid
  }

  private func volumePercentage(for uid: String) -> String {
    guard let volume = inputVolumes[uid] else { return "—" }
    return "\(Int((volume * 100).rounded()))%"
  }

  private func isQuiet(_ uid: String) -> Bool {
    guard let volume = inputVolumes[uid] else { return false }
    return volume < Self.recommendedInputVolume
  }

  private func isVeryQuiet(_ uid: String) -> Bool {
    guard let volume = inputVolumes[uid] else { return false }
    return volume < Self.quietEnoughToExplain
  }

  private func move(_ uid: String, by offset: Int) {
    apply(offset < 0 ? priority.movedUp(uid: uid) : priority.movedDown(uid: uid))
  }

  private func apply(_ updated: MicrophonePriorityList) {
    priority = updated
    AppSettings().microphonePriority = updated
  }

  private func refresh() async {
    scanGeneration += 1
    let mine = scanGeneration
    let scanned = await Task.detached(priority: .userInitiated) {
      let inputs = AudioInputDevices.snapshot()
      let volumes = inputs.devices.reduce(into: [String: Float]()) { volumes, device in
        volumes[device.uid] = AudioInputDevices.inputVolume(device.id)
      }
      return (inputs, volumes)
    }.value
    guard mine == scanGeneration else { return }
    MicrophonePriorityMigration.reconcile(settings: AppSettings(), snapshot: scanned.0)
    priority = AppSettings().microphonePriority
    connected = scanned.0.devices
    inputVolumes = scanned.1
  }
}
