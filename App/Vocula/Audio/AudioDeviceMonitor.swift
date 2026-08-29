import CoreAudio
import Foundation

final class AudioDeviceMonitor: @unchecked Sendable {
  private let device: AudioDeviceID
  private let queue = DispatchQueue(label: "vocula.audio.device-monitor")
  private let openedRate: Double
  private let fired = OneShot()
  private var listener: AudioObjectPropertyListenerBlock?

  private static let watched: [AudioObjectPropertySelector] = [
    kAudioDevicePropertyDeviceIsAlive,
    kAudioDevicePropertyNominalSampleRate,
  ]

  init(
    device: AudioDeviceID,
    openedRate: Double,
    diagnose: (@Sendable (String, String) -> Void)?,
    onLost: @escaping @Sendable (AudioDeviceID) -> Void
  ) {
    self.device = device
    self.openedRate = openedRate

    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      guard let self, self.deviceIsGone else { return }
      if self.fired.fire() { onLost(device) }
    }
    listener = block
    for selector in Self.watched {
      var address = Self.address(selector)
      let status = AudioObjectAddPropertyListenerBlock(device, &address, queue, block)
      if status != noErr { diagnose?("audio.deviceWatchFailed", "code=\(status)") }
    }
  }

  deinit { stop() }

  func stop() {
    guard let listener else { return }
    for selector in Self.watched {
      var address = Self.address(selector)
      AudioObjectRemovePropertyListenerBlock(device, &address, queue, listener)
    }
    self.listener = nil
  }

  private var deviceIsGone: Bool {
    if let alive = Self.flag(device, kAudioDevicePropertyDeviceIsAlive), !alive { return true }
    if let rate = Self.rate(of: device), rate != openedRate { return true }
    return false
  }

  private static func flag(
    _ device: AudioDeviceID,
    _ selector: AudioObjectPropertySelector
  ) -> Bool? {
    var address = address(selector)
    var value = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
    else { return nil }
    return value != 0
  }

  private static func rate(of device: AudioDeviceID) -> Double? {
    var address = address(kAudioDevicePropertyNominalSampleRate)
    var rate = Float64(0)
    var size = UInt32(MemoryLayout<Float64>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr,
      rate > 0
    else { return nil }
    return rate
  }

  private static func address(_ selector: AudioObjectPropertySelector)
    -> AudioObjectPropertyAddress
  {
    AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
  }
}
