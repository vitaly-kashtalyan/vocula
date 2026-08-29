import CoreAudio
import Foundation

final class AudioDeviceListMonitor: @unchecked Sendable {
  private let queue = DispatchQueue(label: "vocula.audio.device-list")
  private var listener: AudioObjectPropertyListenerBlock?

  private static func address() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
  }

  init(
    diagnose: (@Sendable (String, String) -> Void)? = nil,
    onChange: @escaping @Sendable () -> Void
  ) {
    let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
    listener = block
    var address = Self.address()
    let status = AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
    if status != noErr { diagnose?("audio.deviceListWatchFailed", "code=\(status)") }
  }

  deinit { stop() }

  func stop() {
    guard let listener else { return }
    var address = Self.address()
    AudioObjectRemovePropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
    self.listener = nil
  }
}
