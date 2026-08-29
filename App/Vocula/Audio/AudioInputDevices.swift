import CoreAudio
import Foundation
import VoculaKit

struct AudioInputDevice: Identifiable, Hashable, Sendable {
  let id: AudioDeviceID
  let uid: String
  let name: String
  let isBluetooth: Bool
  let opensOnDemandOnly: Bool
}

struct AudioInputSnapshot: Sendable {
  let devices: [AudioInputDevice]
  let builtInID: AudioDeviceID?
  let systemDefaultID: AudioDeviceID?

  var builtInUID: String? { devices.first { $0.id == builtInID }?.uid }
  var builtInName: String? { devices.first { $0.id == builtInID }?.name }
  var systemDefaultUID: String? { devices.first { $0.id == systemDefaultID }?.uid }
  var systemDefaultName: String? { devices.first { $0.id == systemDefaultID }?.name }

  func name(uid: String) -> String? { devices.first { $0.uid == uid }?.name }
}

enum AudioInputDevices {
  static func snapshot() -> AudioInputSnapshot {
    AudioInputSnapshot(
      devices: all,
      builtInID: builtInID,
      systemDefaultID: systemDefaultID)
  }

  static var all: [AudioInputDevice] {
    let started = DispatchTime.now()
    let devices = scan()
    let elapsed = AudioDiagnostics.milliseconds(since: started)
    if elapsed >= AudioDiagnostics.slowScanMilliseconds {
      AudioDiagnostics.record(
        "audio.deviceScan",
        "ms=\(elapsed) count=\(devices.count)")
    }
    return devices
  }

  private static func scan() -> [AudioInputDevice] {
    deviceIDs.compactMap { id in
      guard inputChannelCount(of: id) > 0,
        let uid = string(id, kAudioDevicePropertyDeviceUID),
        let name = string(id, kAudioObjectPropertyName),
        !SyntheticInputDevice.isKnownSynthetic(uid: uid, name: name)
      else { return nil }
      let transport = transportType(of: id)
      return AudioInputDevice(
        id: id, uid: uid, name: name,
        isBluetooth: isBluetooth(transport),
        opensOnDemandOnly: opensOnDemandOnly(transport))
    }
  }

  static func isBluetooth(_ transport: UInt32?) -> Bool {
    transport == kAudioDeviceTransportTypeBluetooth
      || transport == kAudioDeviceTransportTypeBluetoothLE
  }

  static func opensOnDemandOnly(_ transport: UInt32?) -> Bool {
    guard let transport else { return true }
    return isBluetooth(transport)
      || transport == kAudioDeviceTransportTypeContinuityCaptureWired
      || transport == kAudioDeviceTransportTypeContinuityCaptureWireless
  }

  static var systemDefaultID: AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address, 0, nil, &size, &id)
    return status == noErr && id != kAudioObjectUnknown ? id : nil
  }

  static var systemDefaultName: String? {
    guard let id = systemDefaultID else { return nil }
    return all.first { $0.id == id }?.name
  }

  static var systemDefaultUID: String? {
    guard let id = systemDefaultID else { return nil }
    return all.first { $0.id == id }?.uid
  }

  static let builtInMicrophoneUID = "BuiltInMicrophoneDevice"

  static var builtInID: AudioDeviceID? {
    let candidates = deviceIDs.filter { id in
      inputChannelCount(of: id) > 0 && transportType(of: id) == kAudioDeviceTransportTypeBuiltIn
    }
    if let exact = candidates.first(where: {
      string($0, kAudioDevicePropertyDeviceUID) == builtInMicrophoneUID
    }) {
      return exact
    }
    return candidates.first {
      string($0, kAudioDevicePropertyDeviceUID)?.contains("Headphone") != true
    } ?? candidates.first
  }

  static func resolvedDeviceID(for priority: MicrophonePriorityList) -> AudioDeviceID? {
    let connected = all
    let connectedUIDs = Set(connected.map(\.uid))
    if let chosen = priority.firstAvailable(in: connectedUIDs),
      let id = connected.first(where: { $0.uid == chosen.uid })?.id
    {
      return id
    }
    return builtInID
  }

  static func inputVolume(_ id: AudioDeviceID) -> Float? {
    inputProperty(id, kAudioDevicePropertyVolumeScalar, default: Float(0))
  }

  @discardableResult
  static func setInputVolume(_ id: AudioDeviceID, _ value: Float) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyVolumeScalar,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectHasProperty(id, &address) else { return false }
    var settable = DarwinBoolean(false)
    guard AudioObjectIsPropertySettable(id, &address, &settable) == noErr,
      settable.boolValue
    else { return false }
    var volume = min(1, max(0, value))
    return AudioObjectSetPropertyData(
      id, &address, 0, nil,
      UInt32(MemoryLayout<Float>.size), &volume) == noErr
  }

  static func inputIsSilenced(_ id: AudioDeviceID) -> Bool? {
    if inputProperty(id, kAudioDevicePropertyMute, default: UInt32(0)) == 1 { return true }
    guard
      let volume = inputProperty(
        id, kAudioDevicePropertyVolumeScalar,
        default: Float(0))
    else { return nil }
    return volume < 0.01
  }

  private static func inputProperty<T>(
    _ id: AudioDeviceID,
    _ selector: AudioObjectPropertySelector,
    default value: T
  ) -> T? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectHasProperty(id, &address) else { return nil }
    var result = value
    var size = UInt32(MemoryLayout<T>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &result) == noErr else {
      return nil
    }
    return result
  }

  private static func transportType(of id: AudioDeviceID) -> UInt32? {
    var type = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &type) == noErr else {
      return nil
    }
    return type
  }

  static func deviceID(uid: String) -> AudioDeviceID? {
    all.first { $0.uid == uid }?.id
  }

  static func name(uid: String) -> String? {
    all.first { $0.uid == uid }?.name
  }

  private static var deviceIDs: [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(0)
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil, &size) == noErr,
      size > 0
    else { return [] }
    var ids = [AudioDeviceID](
      repeating: 0,
      count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil, &size, &ids) == noErr
    else { return [] }
    return ids
  }

  private static func inputChannelCount(of id: AudioDeviceID) -> UInt32 {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioObjectPropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(0)
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0
    else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(
      byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr
    else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(
      raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + $1.mNumberChannels }
  }

  private static func string(
    _ id: AudioDeviceID,
    _ selector: AudioObjectPropertySelector
  ) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &value) {
      AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
    }
    return status == noErr ? value as String : nil
  }
}
