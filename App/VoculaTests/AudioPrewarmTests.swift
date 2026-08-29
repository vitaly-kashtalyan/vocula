import AVFoundation
import CoreAudio
import Testing
import VoculaKit

@testable import Vocula

private func microphoneIsOpen(_ device: AudioDeviceID) -> Bool {
  var value = UInt32(0)
  var size = UInt32(MemoryLayout<UInt32>.size)
  var address = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
  AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
  return value != 0
}

private func inputIsHeldByAnother() -> Bool {
  guard
    let device =
      AudioInputDevices
      .resolvedDeviceID(for: AppSettings().microphonePriority)
  else { return true }
  for _ in 0..<20 {
    if !microphoneIsOpen(device) { return false }
    Thread.sleep(forTimeInterval: 0.1)
  }
  return true
}

@Suite("Audio prewarm", .serialized)
struct AudioPrewarmTests {
  @Test(
    "prewarming instantiates the input unit WITHOUT opening the microphone",
    .disabled(
      if: inputIsHeldByAnother(),
      "another app has the input open — often Vocula's own level meter"))
  func prewarmDoesNotOpenTheMicrophone() async throws {
    let device = try #require(
      AudioInputDevices.resolvedDeviceID(for: AppSettings().microphonePriority),
      "no input device the priority list resolves to")

    let recorder = AudioRecorder()
    await recorder.prewarm()

    #expect(microphoneIsOpen(device) == false)
  }
}
