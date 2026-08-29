import CoreAudio
import Testing
import VoculaKit

@testable import Vocula

@Suite("Audio input devices")
struct AudioInputDevicesTests {
  @Test("every Mac offers at least one input, and each is usable as identity")
  func enumerated() throws {
    let devices = AudioInputDevices.all
    try #require(!devices.isEmpty, "no input device on this Mac")
    #expect(devices.allSatisfy { !$0.uid.isEmpty && !$0.name.isEmpty })
    #expect(Set(devices.map(\.uid)).count == devices.count)
    #expect(Set(devices.map(\.id)).count == devices.count)
  }

  @Test("the system default input is one of the listed devices")
  func defaultIsListed() throws {
    let id = try #require(AudioInputDevices.systemDefaultID, "no default input device")
    #expect(AudioInputDevices.all.contains { $0.id == id })
  }

  @Test("a uid round-trips to the same device")
  func lookup() throws {
    let device = try #require(AudioInputDevices.all.first)
    #expect(AudioInputDevices.deviceID(uid: device.uid) == device.id)
    #expect(AudioInputDevices.name(uid: device.uid) == device.name)
  }

  @Test("a uid that is not plugged in resolves to nothing")
  func unknownUID() {
    #expect(AudioInputDevices.deviceID(uid: "no.such.device.uid") == nil)
    #expect(AudioInputDevices.name(uid: "no.such.device.uid") == nil)
  }
}

@Suite("The built-in microphone is not the headphone jack")
struct BuiltInIdentityTests {
  static var hasAnInput: Bool { AudioInputDevices.builtInID != nil }

  static var hasTheBuiltInMicrophone: Bool {
    AudioInputDevices.all.contains { $0.uid == AudioInputDevices.builtInMicrophoneUID }
  }

  @Test(
    "the built-in resolves to the microphone, never to the jack input",
    .enabled(if: BuiltInIdentityTests.hasAnInput, "this Mac reports no input device"))
  func builtInIsTheMicrophone() throws {
    let id = try #require(AudioInputDevices.builtInID)
    let uid = try #require(AudioInputDevices.all.first { $0.id == id }?.uid)
    #expect(
      !uid.contains("Headphone"),
      "the jack input was taken for the built-in microphone")
  }

  @Test(
    "when the microphone is present it is the one chosen",
    .enabled(
      if: BuiltInIdentityTests.hasTheBuiltInMicrophone,
      "this Mac reports no built-in microphone"))
  func exactUIDWins() throws {
    let devices = AudioInputDevices.all
    let id = try #require(AudioInputDevices.builtInID)
    #expect(devices.first { $0.id == id }?.uid == AudioInputDevices.builtInMicrophoneUID)
  }
}

@Suite("Priority resolution fallback")
struct PriorityResolutionFallbackTests {
  @Test("an empty priority list falls back to the built-in, not to whatever macOS made default")
  func fallbackIsTheBuiltIn() {
    let resolved = AudioInputDevices.resolvedDeviceID(for: MicrophonePriorityList(devices: []))
    #expect(resolved == AudioInputDevices.builtInID)
  }

  @Test("a priority list naming only absent devices falls back the same way")
  func absentDevicesFallBackToTheBuiltIn() {
    let ghost = RankedInputDevice(uid: "no-such-device-uid", name: "Ghost")
    let resolved = AudioInputDevices.resolvedDeviceID(
      for: MicrophonePriorityList(devices: [ghost]))
    #expect(resolved == AudioInputDevices.builtInID)
  }
}

@Suite("Which inputs may be opened unasked")
struct InputTransportTests {
  @Test(
    "a radio-linked transport is never opened for a meter unasked",
    arguments: [
      kAudioDeviceTransportTypeBluetooth,
      kAudioDeviceTransportTypeBluetoothLE,
      kAudioDeviceTransportTypeContinuityCaptureWired,
      kAudioDeviceTransportTypeContinuityCaptureWireless,
    ])
  func radioLinkedNeedsAsking(_ transport: UInt32) {
    #expect(AudioInputDevices.opensOnDemandOnly(transport))
  }

  @Test(
    "a wired transport is opened as soon as the section is in front",
    arguments: [
      kAudioDeviceTransportTypeBuiltIn,
      kAudioDeviceTransportTypeUSB,
      kAudioDeviceTransportTypeAggregate,
    ])
  func wiredOpensOnItsOwn(_ transport: UInt32) {
    #expect(!AudioInputDevices.opensOnDemandOnly(transport))
  }

  @Test("a transport that would not read is treated as radio-linked")
  func unreadableTransportFailsSafe() {
    #expect(AudioInputDevices.opensOnDemandOnly(nil))
  }

  @Test("only Bluetooth carries the narrowband warning")
  func bluetoothWarningIsNarrow() {
    #expect(AudioInputDevices.isBluetooth(kAudioDeviceTransportTypeBluetooth))
    #expect(AudioInputDevices.isBluetooth(kAudioDeviceTransportTypeBluetoothLE))
    #expect(!AudioInputDevices.isBluetooth(kAudioDeviceTransportTypeContinuityCaptureWireless))
    #expect(!AudioInputDevices.isBluetooth(nil))
  }
}
