import CoreAudio
import Foundation
import Synchronization
import VoculaKit

actor SystemAudioTap: MeetingTrackSource {
  typealias Outputs =
    @Sendable () -> (candidates: [MeetingOutputCandidate], defaultOutputUID: String?)

  static let queue = DispatchSerialQueue(label: "vocula.meeting.tap")

  static let liveOutputs: Outputs = {
    let candidates = devices().compactMap { device -> MeetingOutputCandidate? in
      guard let uid = uid(of: device) else { return nil }
      var transport = UInt32(0)
      _ = read(device, kAudioDevicePropertyTransportType, &transport)
      return MeetingOutputCandidate(
        uid: uid, isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn,
        outputStreams: streams(of: device, kAudioObjectPropertyScopeOutput),
        inputStreams: streams(of: device, kAudioObjectPropertyScopeInput))
    }
    var output = AudioObjectID(kAudioObjectUnknown)
    let found =
      read(
        AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, &output)
      == noErr
    return (candidates, found ? uid(of: output) : nil)
  }

  nonisolated var unownedExecutor: UnownedSerialExecutor { Self.queue.asUnownedSerialExecutor() }

  private let outputs: Outputs
  private let ioQueue = DispatchQueue(label: "vocula.meeting.tap.io", qos: .userInteractive)
  private let resampler = MeetingResampler()
  private let abandoned = Mutex(false)
  private let buffer = Mutex<TrackBuffer?>(nil)
  private var tap = AudioObjectID(kAudioObjectUnknown)
  private var aggregate = AudioObjectID(kAudioObjectUnknown)
  private var formatListener: AudioObjectPropertyListenerBlock?
  private var ioProc: AudioDeviceIOProcID?

  init(outputs: @escaping Outputs = SystemAudioTap.liveOutputs) {
    self.outputs = outputs
  }

  func start() async throws {
    try refuseIfAbandoned()
    guard !VoculaAppDelegate.isSecondCopy else { throw MeetingFailure.secondCopy }
    let (candidates, defaultOutputUID) = outputs()
    guard
      let clock = MeetingClockDevice.choose(among: candidates, defaultOutputUID: defaultOutputUID)
    else { throw MeetingFailure.failed(step: "output", code: 0) }
    do {
      try open(clock: clock.uid)
      try refuseIfAbandoned()
    } catch {
      teardown()
      throw error
    }
  }

  nonisolated func stop() {
    abandoned.withLock { $0 = true }
    Task { await teardown() }
  }

  func finished() async { teardown() }

  nonisolated func drain() -> TrackDrain {
    guard let buffer = buffer.withLock({ $0 }) else { return TrackDrain() }
    return resampler.drain(buffer)
  }

  nonisolated var callbacks: Int { buffer.withLock { $0 }?.callbacks ?? 0 }

  static func composition(clockUID: String, tapUUID: UUID, aggregateUID: String) -> [String: Any]? {
    guard !clockUID.isEmpty else { return nil }
    return [
      kAudioAggregateDeviceNameKey: MeetingAggregate.name,
      kAudioAggregateDeviceUIDKey: aggregateUID,
      kAudioAggregateDeviceMainSubDeviceKey: clockUID,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: clockUID]],
      kAudioAggregateDeviceTapListKey: [
        [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUUID.uuidString]
      ],
    ]
  }

  private func refuseIfAbandoned() throws {
    guard abandoned.withLock({ $0 }) else { return }
    throw MeetingFailure.failed(step: "abandoned", code: 0)
  }

  private func open(clock: String) throws {
    var process = AudioObjectID(kAudioObjectUnknown)
    var pid = getpid()
    var address = Self.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    try Self.check(
      "process",
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size),
        &pid, &size, &process), made: process)

    let description = CATapDescription(monoGlobalTapButExcludeProcesses: [process])
    description.isPrivate = true
    description.muteBehavior = .unmuted
    try Self.check("tap", AudioHardwareCreateProcessTap(description, &tap), made: tap)

    guard
      let composition = Self.composition(
        clockUID: clock, tapUUID: description.uuid, aggregateUID: MeetingAggregate.uid(UUID()))
    else { throw MeetingFailure.failed(step: "aggregate", code: 0) }
    try Self.check(
      "aggregate", AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate),
      made: aggregate)

    var format = AudioStreamBasicDescription()
    try Self.check("format", Self.read(tap, kAudioTapPropertyFormat, &format))
    guard Self.isMonoFloat(format), let buffer = TrackBuffer(rate: format.mSampleRate) else {
      throw MeetingFailure.failed(step: "format", code: 0)
    }
    self.buffer.withLock { $0 = buffer }
    let listener = Self.followRate(of: tap, into: buffer)
    var formatAddress = Self.address(kAudioTapPropertyFormat)
    try Self.check(
      "format", AudioObjectAddPropertyListenerBlock(tap, &formatAddress, Self.queue, listener))
    formatListener = listener

    try Self.check(
      "ioproc",
      AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, ioQueue, Self.capture(into: buffer)))
    try Self.check("start", AudioDeviceStart(aggregate, ioProc))
  }

  private func teardown() {
    if let ioProc {
      AudioDeviceStop(aggregate, ioProc)
      AudioDeviceDestroyIOProcID(aggregate, ioProc)
      self.ioProc = nil
    }
    if let formatListener {
      var address = Self.address(kAudioTapPropertyFormat)
      AudioObjectRemovePropertyListenerBlock(tap, &address, Self.queue, formatListener)
      self.formatListener = nil
    }
    if aggregate != kAudioObjectUnknown {
      AudioHardwareDestroyAggregateDevice(aggregate)
      aggregate = AudioObjectID(kAudioObjectUnknown)
    }
    if tap != kAudioObjectUnknown {
      AudioHardwareDestroyProcessTap(tap)
      tap = AudioObjectID(kAudioObjectUnknown)
    }
  }

  private static func capture(into buffer: TrackBuffer) -> AudioDeviceIOBlock {
    { _, input, inputTime, _, _ in
      let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
      guard
        let index = MeetingTapStream.index(
          bufferCount: list.count, lastBufferChannels: list.last?.mNumberChannels ?? 0),
        let data = list[index].mData
      else { return }
      let stamp = inputTime.pointee
      let host =
        stamp.mFlags.contains(.hostTimeValid) ? stamp.mHostTime : AudioGetCurrentHostTime()
      buffer.write(
        UnsafeBufferPointer(
          start: data.assumingMemoryBound(to: Float.self),
          count: Int(list[index].mDataByteSize) / MemoryLayout<Float>.size),
        hostNanos: AudioConvertHostTimeToNanos(host))
    }
  }

  private static func followRate(of tap: AudioObjectID, into buffer: TrackBuffer)
    -> AudioObjectPropertyListenerBlock
  {
    { _, _ in
      var format = AudioStreamBasicDescription()
      guard read(tap, kAudioTapPropertyFormat, &format) == noErr else { return }
      buffer.setRate(format.mSampleRate)
    }
  }

  private static func isMonoFloat(_ format: AudioStreamBasicDescription) -> Bool {
    format.mFormatID == kAudioFormatLinearPCM && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
      && format.mBitsPerChannel == 32 && format.mChannelsPerFrame == 1
  }

  private static func check(_ step: String, _ status: OSStatus) throws {
    guard status == noErr else { throw MeetingFailure.failed(step: step, code: status) }
  }

  private static func check(_ step: String, _ status: OSStatus, made object: AudioObjectID) throws {
    try check(step, status)
    guard object != kAudioObjectUnknown else { throw MeetingFailure.failed(step: step, code: 0) }
  }

  private static func address(
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }

  private static func read<Value: BitwiseCopyable>(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout Value
  ) -> OSStatus {
    var address = address(selector)
    var size = UInt32(MemoryLayout<Value>.size)
    return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
  }

  private static func uid(of device: AudioObjectID) -> String? {
    var address = address(kAudioDevicePropertyDeviceUID)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
      let value
    else { return nil }
    return value.takeRetainedValue() as String
  }

  private static func streams(of device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
    var address = address(kAudioDevicePropertyStreams, scope)
    var size = UInt32(0)
    guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else {
      return 0
    }
    return Int(size) / MemoryLayout<AudioStreamID>.size
  }

  private static func devices() -> [AudioObjectID] {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var address = address(kAudioHardwarePropertyDevices)
    var size = UInt32(0)
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
      return []
    }
    var ids = [AudioObjectID](
      repeating: AudioObjectID(kAudioObjectUnknown),
      count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else {
      return []
    }
    return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
  }
}
