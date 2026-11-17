import AudioToolbox
import CoreAudio
import Foundation
import VoculaKit

private let meetingInputCallback: AURenderCallback = { refCon, flags, timeStamp, bus, frames, _ in
  let input = Unmanaged<MeetingMicrophone.Input>.fromOpaque(refCon).takeUnretainedValue()
  let stamp = timeStamp.pointee
  let host =
    stamp.mFlags.contains(.hostTimeValid) ? stamp.mHostTime : AudioGetCurrentHostTime()
  return input.capture.deliver(frames: frames, hostNanos: AudioConvertHostTimeToNanos(host)) {
    AudioUnitRender(input.unit, flags, timeStamp, bus, frames, $0)
  }
}

final class MeetingMicrophone: MeetingTrackSource, @unchecked Sendable {
  final class Capture: @unchecked Sendable {
    let buffer: TrackBuffer
    private let list: UnsafeMutableAudioBufferListPointer
    private let samples: UnsafeMutablePointer<Float>
    private let maximumFrames: UInt32

    init?(channels: Int, maximumFrames: UInt32, rate: Double) {
      guard channels > 0, maximumFrames > 0, let buffer = TrackBuffer(rate: rate) else {
        return nil
      }
      self.buffer = buffer
      self.maximumFrames = maximumFrames
      let frames = Int(maximumFrames)
      samples = .allocate(capacity: channels * frames)
      samples.initialize(repeating: 0, count: channels * frames)
      list = AudioBufferList.allocate(maximumBuffers: channels)
      for index in 0..<channels {
        list[index] = AudioBuffer(
          mNumberChannels: 1, mDataByteSize: 0,
          mData: UnsafeMutableRawPointer(samples + index * frames))
      }
    }

    deinit {
      samples.deallocate()
      free(list.unsafeMutablePointer)
    }

    func deliver(
      frames: UInt32, hostNanos: UInt64,
      render: (UnsafeMutablePointer<AudioBufferList>) -> OSStatus
    ) -> OSStatus {
      let capacity = maximumFrames * UInt32(MemoryLayout<Float>.size)
      for index in 0..<list.count { list[index].mDataByteSize = capacity }
      guard frames <= maximumFrames else { return kAudio_ParamError }
      let status = render(list.unsafeMutablePointer)
      guard status == noErr else { return status }
      buffer.write(UnsafeBufferPointer(start: samples, count: Int(frames)), hostNanos: hostNanos)
      return noErr
    }
  }

  fileprivate final class Input: @unchecked Sendable {
    let unit: AudioUnit
    let capture: Capture

    init(unit: AudioUnit, capture: Capture) {
      self.unit = unit
      self.capture = capture
    }

    func open(_ device: AudioDeviceID, format: CaptureFormat, maximumFrames: UInt32) throws {
      try check(
        "enableIO", set(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, UInt32(1)))
      try check(
        "enableIO", set(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, UInt32(0)))
      try check(
        "device", set(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, device))
      try check(
        "format",
        set(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, Self.client(format)))
      try check(
        "frames",
        set(kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, maximumFrames))
      let callback = AURenderCallbackStruct(
        inputProc: meetingInputCallback, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
      try check(
        "callback",
        set(kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, callback))
      try check("initialize", AudioUnitInitialize(unit))
      try check("start", AudioOutputUnitStart(unit))
    }

    func close() {
      AudioOutputUnitStop(unit)
      AudioUnitUninitialize(unit)
      AudioComponentInstanceDispose(unit)
    }

    private func set<Value: BitwiseCopyable>(
      _ property: AudioUnitPropertyID, _ scope: AudioUnitScope, _ element: AudioUnitElement,
      _ value: Value
    ) -> OSStatus {
      var value = value
      return AudioUnitSetProperty(
        unit, property, scope, element, &value, UInt32(MemoryLayout<Value>.size))
    }

    private func check(_ step: String, _ status: OSStatus) throws {
      guard status == noErr else { throw MeetingFailure.failed(step: step, code: status) }
    }

    private static func client(_ format: CaptureFormat) -> AudioStreamBasicDescription {
      let bytes = UInt32(MemoryLayout<Float>.size)
      return AudioStreamBasicDescription(
        mSampleRate: format.rate, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
          | kAudioFormatFlagIsNonInterleaved,
        mBytesPerPacket: bytes, mFramesPerPacket: 1, mBytesPerFrame: bytes,
        mChannelsPerFrame: UInt32(format.channels), mBitsPerChannel: bytes * 8, mReserved: 0)
    }
  }

  static let liveChoice: @Sendable () -> UInt32? = {
    MeetingMicrophoneRule.device(
      resolved: AudioInputDevices.resolvedDeviceID(for: AppSettings().microphonePriority),
      among: AudioInputDevices.all.map {
        MeetingInputCandidate(id: $0.id, opensOnDemandOnly: $0.opensOnDemandOnly)
      })
  }

  private let onEnded: @Sendable () async -> Void
  private let chooseDevice: @Sendable () -> UInt32?
  private let ended = OneShot()
  private let resampler = MeetingResampler()
  private let lock = NSLock()
  private var stopped = false
  var buffer: TrackBuffer?
  private var input: Input?
  private var monitor: AudioDeviceMonitor?
  private var poll: Task<Void, Never>?

  init(
    onEnded: @escaping @Sendable () async -> Void,
    chooseDevice: @escaping @Sendable () -> UInt32? = MeetingMicrophone.liveChoice
  ) {
    self.onEnded = onEnded
    self.chooseDevice = chooseDevice
  }

  deinit { close() }

  func start() async throws {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(with: Result { try self.openChosenDevice() })
      }
    }
  }

  private func openChosenDevice() throws {
    try refuseIfStopped()
    guard !VoculaAppDelegate.isSecondCopy else { throw MeetingFailure.secondCopy }
    guard let device = chooseDevice() else { throw MeetingFailure.notOpened }
    guard let format = AUHALInputUnit.hardwareFormat(of: device) else {
      throw MeetingFailure.failed(step: "format", code: 0)
    }
    try refuseIfStopped()
    let input = try Self.open(device, format: format)
    try lock.withLock {
      guard !stopped else {
        input.close()
        throw MeetingFailure.failed(step: "stopped", code: 0)
      }
      self.input = input
      buffer = input.capture.buffer
      monitor = AudioDeviceMonitor(device: device, openedRate: format.rate, diagnose: nil) {
        [weak self] _ in Task { self?.end() }
      }
      poll = Task { [weak self, buffer = input.capture.buffer] in
        var watchdog = InputLivenessWatchdog()
        while !Task.isCancelled {
          do { try await Task.sleep(for: InputLivenessWatchdog.checkInterval) } catch { return }
          if watchdog.check(buffersDelivered: buffer.callbacks) == .dead { self?.end() }
        }
      }
    }
  }

  func stop() {
    _ = ended.fire()
    lock.withLock {
      stopped = true
      close()
    }
  }

  func finished() async {}

  func drain() -> TrackDrain {
    let (held, isLast) = lock.withLock { (buffer, stopped) }
    guard let held else { return TrackDrain() }
    let drained = resampler.drain(held)
    if isLast { lock.withLock { buffer = nil } }
    return drained
  }

  var callbacks: Int { lock.withLock { buffer }?.callbacks ?? 0 }

  private func refuseIfStopped() throws {
    guard lock.withLock({ stopped }) else { return }
    throw MeetingFailure.failed(step: "stopped", code: 0)
  }

  private func end() {
    guard ended.fire() else { return }
    lock.withLock { close() }
    let onEnded = onEnded
    Task { await onEnded() }
  }

  private func close() {
    poll?.cancel()
    poll = nil
    monitor?.stop()
    monitor = nil
    input?.close()
    input = nil
  }

  private static func open(_ device: AudioDeviceID, format: CaptureFormat) throws -> Input {
    let maximumFrames = AUHALInputUnit.bufferFrameSize(of: device)
    var description = AudioComponentDescription(
      componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
      componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0,
      componentFlagsMask: 0)
    guard let component = AudioComponentFindNext(nil, &description) else {
      throw MeetingFailure.failed(step: "unit", code: 0)
    }
    var unit: AudioUnit?
    let made = AudioComponentInstanceNew(component, &unit)
    guard made == noErr, let unit else { throw MeetingFailure.failed(step: "unit", code: made) }
    guard
      let capture = Capture(
        channels: format.channels, maximumFrames: maximumFrames, rate: format.rate)
    else {
      AudioComponentInstanceDispose(unit)
      throw MeetingFailure.failed(step: "format", code: 0)
    }
    let input = Input(unit: unit, capture: capture)
    do {
      try input.open(device, format: format, maximumFrames: maximumFrames)
    } catch {
      input.close()
      throw error
    }
    return input
  }
}
