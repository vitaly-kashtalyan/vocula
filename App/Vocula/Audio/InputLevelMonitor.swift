import AVFoundation
import CoreAudio
import VoculaKit

actor InputLevelMonitor {
  private var unit: AUHALInputUnit?
  private var openDevice: AudioDeviceID?
  private let levels = StreamFanout<Float>()

  private static let queue = DispatchQueue(label: "app.vocula.input-level")

  nonisolated func levelUpdates() -> AsyncStream<Float> { levels.subscribe() }

  deinit { levels.finishAll() }

  @discardableResult
  func listen(to device: AudioDeviceID) async -> Bool {
    guard !VoculaAppDelegate.isSecondCopy else { return false }
    guard openDevice != device else { return true }
    stop()
    let started = DispatchTime.now()
    let levels = self.levels
    let outcome: (unit: AUHALInputUnit?, cause: String) =
      await withCheckedContinuation { continuation in
        Self.queue.async {
          continuation.resume(returning: Self.open(device, levels: levels))
        }
      }
    unit = outcome.unit
    openDevice = outcome.unit == nil ? nil : device
    let elapsed = AudioDiagnostics.milliseconds(since: started)
    if outcome.unit == nil || elapsed >= AudioDiagnostics.slowOpenMilliseconds {
      AudioDiagnostics.record(
        "audio.meterOpen",
        "ms=\(elapsed) ok=\(outcome.unit != nil)" + outcome.cause)
    }
    return outcome.unit != nil
  }

  func stop() {
    let closing = unit
    unit = nil
    openDevice = nil
    levels.emit(0)
    guard let closing else { return }
    Self.queue.async { closing.stop() }
  }

  private static func open(
    _ device: AudioDeviceID,
    levels: StreamFanout<Float>
  ) -> (AUHALInputUnit?, String) {
    guard let hardware = AUHALInputUnit.hardwareFormat(of: device),
      let client = CaptureFormat.client(
        hardwareRate: hardware.rate,
        hardwareChannels: hardware.channels)
    else { return (nil, " step=format") }
    let frames = AUHALInputUnit.bufferFrameSize(of: device)
    guard
      let sink = CaptureSink(
        clientFormat: client,
        frameCapacity: frames,
        accumulator: nil,
        levels: levels,
        counter: BufferCounter(),
        diagnose: { AudioDiagnostics.record($0, $1) })
    else { return (nil, " step=sink") }
    do {
      let opened = try AUHALInputUnit(
        deviceID: device, sink: sink,
        maximumFrames: frames)
      try opened.start()
      return (opened, "")
    } catch let failure as AUHALError {
      return (nil, " step=\(failure.step) code=\(failure.status)")
    } catch {
      return (nil, " step=open")
    }
  }
}
