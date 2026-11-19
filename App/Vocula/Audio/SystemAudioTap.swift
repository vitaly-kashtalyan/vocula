import CoreAudio
import Foundation
import Synchronization
import VoculaKit

actor SystemAudioTap: MeetingTrackSource {
  typealias Outputs =
    @Sendable () throws -> (candidates: [MeetingOutputCandidate], defaultOutputUID: String?)

  static let queue = DispatchSerialQueue(label: "vocula.meeting.tap")

  static let liveOutputs: Outputs = {
    let system = AudioObjectID(kAudioObjectSystemObject)
    let devices = try objects(system, kAudioHardwarePropertyDevices, step: "output")
    let candidates = devices.compactMap { device -> MeetingOutputCandidate? in
      var transport = UInt32(0)
      guard let uid = uid(of: device),
        read(device, kAudioDevicePropertyTransportType, &transport) == noErr,
        let outputStreams = try? objects(
          device, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput, step: "output"),
        let inputStreams = try? objects(
          device, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput, step: "output")
      else { return nil }
      return MeetingOutputCandidate(
        uid: uid, isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn,
        outputStreams: outputStreams.count, inputStreams: inputStreams.count)
    }
    var output = AudioObjectID(kAudioObjectUnknown)
    let found = read(system, kAudioHardwarePropertyDefaultOutputDevice, &output) == noErr
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
  private var rateWatch: RateWatch?
  private var watchingRate = false
  private var ioProc: AudioDeviceIOProcID?

  init(outputs: @escaping Outputs = SystemAudioTap.liveOutputs) {
    self.outputs = outputs
  }

  func start() async throws {
    try refuseIfAbandoned()
    guard !VoculaAppDelegate.isSecondCopy else { throw MeetingFailure.secondCopy }
    let (candidates, defaultOutputUID) = try outputs()
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
      kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: clockUID]],
      kAudioAggregateDeviceTapListKey: [
        [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUUID.uuidString]
      ],
    ]
  }

  static func captureRate(
    inputStreams: [AudioStreamID], format: (AudioStreamID) -> AudioStreamBasicDescription?
  ) -> Double? {
    guard inputStreams.count == 1, let format = format(inputStreams[0]),
      format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
      format.mBitsPerChannel == 32, format.mChannelsPerFrame == 1
    else { return nil }
    return format.mSampleRate
  }

  private var rateSources: [(object: AudioObjectID, selector: AudioObjectPropertySelector)] {
    [(tap, kAudioTapPropertyFormat), (aggregate, kAudioDevicePropertyNominalSampleRate)]
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

    guard let rate = Self.liveRate(of: aggregate), let buffer = TrackBuffer(rate: rate) else {
      throw MeetingFailure.failed(step: "format", code: 0)
    }
    self.buffer.withLock { $0 = buffer }
    let watch = RateWatch(aggregate: aggregate, buffer: buffer)
    rateWatch = watch
    watchingRate = true
    for source in rateSources {
      var address = Self.address(source.selector)
      try Self.check(
        "format",
        AudioObjectAddPropertyListener(
          source.object, &address, Self.followRate, Unmanaged.passUnretained(watch).toOpaque()))
    }

    try Self.check(
      "ioproc",
      AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, ioQueue, Self.capture(into: buffer)))
    try refuseIfAbandoned()
    try Self.check("start", AudioDeviceStart(aggregate, ioProc))
  }

  private func teardown() {
    if let ioProc {
      AudioDeviceStop(aggregate, ioProc)
      AudioDeviceDestroyIOProcID(aggregate, ioProc)
      self.ioProc = nil
    }
    if watchingRate, let rateWatch {
      for source in rateSources {
        var address = Self.address(source.selector)
        AudioObjectRemovePropertyListener(
          source.object, &address, Self.followRate, Unmanaged.passUnretained(rateWatch).toOpaque())
      }
      watchingRate = false
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

  private final class RateWatch: Sendable {
    let aggregate: AudioObjectID
    let buffer: TrackBuffer

    init(aggregate: AudioObjectID, buffer: TrackBuffer) {
      self.aggregate = aggregate
      self.buffer = buffer
    }
  }

  // Workaround: Swift re-bridges a listener block on each call, so its removal never matches;
  // the HAL may call this C proc on the main thread, so it only hops to the tap queue.
  private static let followRate: AudioObjectPropertyListenerProc = { _, _, _, context in
    guard let context else { return noErr }
    let watch = Unmanaged<RateWatch>.fromOpaque(context).takeUnretainedValue()
    queue.async {
      if let rate = liveRate(of: watch.aggregate) { watch.buffer.setRate(rate) }
    }
    return noErr
  }

  private static func liveRate(of aggregate: AudioObjectID) -> Double? {
    captureRate(
      inputStreams: (try? objects(
        aggregate, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput, step: "format"))
        ?? [],
      format: { stream in
        var format = AudioStreamBasicDescription()
        return read(stream, kAudioStreamPropertyVirtualFormat, &format) == noErr ? format : nil
      })
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

  private static func objects(
    _ owner: AudioObjectID, _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, step: String
  ) throws -> [AudioObjectID] {
    var address = address(selector, scope)
    var size = UInt32(0)
    try check(step, AudioObjectGetPropertyDataSize(owner, &address, 0, nil, &size))
    var ids = [AudioObjectID](
      repeating: AudioObjectID(kAudioObjectUnknown),
      count: Int(size) / MemoryLayout<AudioObjectID>.size)
    try check(step, AudioObjectGetPropertyData(owner, &address, 0, nil, &size, &ids))
    return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
  }
}
