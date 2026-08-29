import AVFoundation
import AudioToolbox
import CoreAudio
import VoculaKit

struct AUHALError: Error {
  let step: String
  let status: OSStatus

  var asNSError: NSError { NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
}

final class BufferCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  func increment() { lock.withLock { count += 1 } }
  func reset() { lock.withLock { count = 0 } }
  var value: Int { lock.withLock { count } }
}

final class ConverterCache: @unchecked Sendable {
  private let target: AVAudioFormat
  private var cached: (format: AVAudioFormat, converter: AVAudioConverter)?

  init(target: AVAudioFormat) { self.target = target }

  func converter(for format: AVAudioFormat) -> AVAudioConverter? {
    if let cached, cached.format == format { return cached.converter }
    guard let made = AudioRecorder.makeConverter(from: format, to: target) else { return nil }
    cached = (format, made)
    return made
  }
}

final class OneShot: @unchecked Sendable {
  private let lock = NSLock()
  private var spent = false
  func fire() -> Bool {
    lock.withLock {
      if spent { return false }
      spent = true
      return true
    }
  }
}

final class CaptureSink: @unchecked Sendable {
  private let target: AVAudioFormat
  private let accumulator: AudioAccumulator?
  private let levels: StreamFanout<Float>
  private let counter: BufferCounter
  private let diagnose: (@Sendable (String, String) -> Void)?
  private let converters: ConverterCache
  private let conversionFailed = OneShot()
  private let renderFailed = OneShot()
  private var framesSinceLevel: AVAudioFrameCount = 0
  private let framesPerLevel: AVAudioFrameCount
  let renderBuffer: AVAudioPCMBuffer

  init?(
    clientFormat: CaptureFormat,
    frameCapacity: AVAudioFrameCount,
    accumulator: AudioAccumulator?,
    levels: StreamFanout<Float>,
    counter: BufferCounter,
    diagnose: (@Sendable (String, String) -> Void)?
  ) {
    guard
      let source = Self.floatFormat(
        rate: clientFormat.rate,
        channels: clientFormat.channels),
      let target = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioFormat.sampleRate,
        channels: AVAudioChannelCount(AudioFormat.channels),
        interleaved: false),
      let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frameCapacity)
    else { return nil }
    self.target = target
    self.accumulator = accumulator
    self.levels = levels
    self.counter = counter
    self.diagnose = diagnose
    self.converters = ConverterCache(target: target)
    self.renderBuffer = buffer
    self.framesPerLevel = AVAudioFrameCount(clientFormat.rate / Self.levelsPerSecond)
  }

  func deliver(frames: AVAudioFrameCount) {
    counter.increment()
    guard accumulator?.beginSlice() ?? true else { return }
    renderBuffer.frameLength = frames
    let slice =
      converters.converter(for: renderBuffer.format)
      .map { AudioRecorder.convert(renderBuffer, with: $0, to: target) } ?? nil
    if slice == nil, conversionFailed.fire() {
      diagnose?("audio.conversionFailed", "")
    }
    if let slice {
      framesSinceLevel += frames
      if framesSinceLevel >= framesPerLevel {
        framesSinceLevel = 0
        levels.emit(PCMSamples.rms(slice[...]))
      }
    }
    accumulator?.finishSlice(slice)
  }

  static let levelsPerSecond: Double = 38

  func renderDidFail(_ status: OSStatus) {
    if renderFailed.fire() { diagnose?("audio.renderFailed", "code=\(status)") }
  }

  static func floatFormat(rate: Double, channels: Int) -> AVAudioFormat? {
    guard channels > 0 else { return nil }
    if channels <= 2 {
      return AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: rate,
        channels: AVAudioChannelCount(channels),
        interleaved: false)
    }
    let tag = kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)
    guard let layout = AVAudioChannelLayout(layoutTag: tag) else { return nil }
    return AVAudioFormat(standardFormatWithSampleRate: rate, channelLayout: layout)
  }
}

private let inputCallback: AURenderCallback = { refCon, flags, timeStamp, bus, frames, _ in
  let unit = Unmanaged<AUHALInputUnit>.fromOpaque(refCon).takeUnretainedValue()
  return unit.render(flags: flags, timeStamp: timeStamp, bus: bus, frames: frames)
}

final class AUHALInputUnit: @unchecked Sendable {
  private let unit: AudioUnit
  private let sink: CaptureSink
  private var started = false
  private var disposed = false

  static func hardwareFormat(of device: AudioDeviceID) -> CaptureFormat? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamFormat,
      mScope: kAudioObjectPropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain)
    var asbd = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &asbd) == noErr
    else { return nil }
    return CaptureFormat.client(
      hardwareRate: asbd.mSampleRate,
      hardwareChannels: Int(asbd.mChannelsPerFrame))
  }

  // The device's buffer size is machine-wide; AudioUnitRender fails with -10874 below it.
  static func bufferFrameSize(of device: AudioDeviceID) -> AVAudioFrameCount {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyBufferFrameSize,
      mScope: kAudioObjectPropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain)
    var frames = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &frames) == noErr,
      frames > 0
    else { return 4096 }
    return AVAudioFrameCount(frames)
  }

  init(deviceID: AudioDeviceID, sink: CaptureSink, maximumFrames: AVAudioFrameCount) throws {
    var description = AudioComponentDescription(
      componentType: kAudioUnitType_Output,
      componentSubType: kAudioUnitSubType_HALOutput,
      componentManufacturer: kAudioUnitManufacturer_Apple,
      componentFlags: 0, componentFlagsMask: 0)
    guard let component = AudioComponentFindNext(nil, &description) else {
      throw AUHALError(step: "find", status: -1)
    }
    var instance: AudioUnit?
    try Self.check("new", AudioComponentInstanceNew(component, &instance))
    guard let instance else { throw AUHALError(step: "new", status: -1) }
    self.unit = instance
    self.sink = sink

    var enable: UInt32 = 1
    try Self.check(
      "enableInput",
      AudioUnitSetProperty(
        instance, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
        &enable, UInt32(MemoryLayout<UInt32>.size)))
    var disable: UInt32 = 0
    try Self.check(
      "disableOutput",
      AudioUnitSetProperty(
        instance, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
        &disable, UInt32(MemoryLayout<UInt32>.size)))

    var device = deviceID
    try Self.check(
      "setDevice",
      AudioUnitSetProperty(
        instance, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
        &device, UInt32(MemoryLayout<AudioDeviceID>.size)))

    var client = sink.renderBuffer.format.streamDescription.pointee
    try Self.check(
      "setFormat",
      AudioUnitSetProperty(
        instance, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
        &client, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))

    var maximum = UInt32(maximumFrames)
    try Self.check(
      "setMaxFrames",
      AudioUnitSetProperty(
        instance, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
        &maximum, UInt32(MemoryLayout<UInt32>.size)))

    var callback = AURenderCallbackStruct(
      inputProc: inputCallback,
      inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
    try Self.check(
      "setCallback",
      AudioUnitSetProperty(
        instance, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
        &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))

    try Self.check("initialize", AudioUnitInitialize(instance))
  }

  var heldDeviceID: AudioDeviceID {
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioUnitGetProperty(
      unit, kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global, 0, &device, &size)
    return device
  }

  func start() throws {
    try Self.check("start", AudioOutputUnitStart(unit))
    started = true
  }

  func stop() {
    guard !disposed else { return }
    disposed = true
    if started {
      AudioOutputUnitStop(unit)
      started = false
    }
    AudioUnitUninitialize(unit)
    AudioComponentInstanceDispose(unit)
  }

  deinit { stop() }

  fileprivate func render(
    flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    timeStamp: UnsafePointer<AudioTimeStamp>,
    bus: UInt32,
    frames: UInt32
  ) -> OSStatus {
    let list = sink.renderBuffer.mutableAudioBufferList
    let capacity = sink.renderBuffer.frameCapacity * 4
    let buffers = UnsafeMutableAudioBufferListPointer(list)
    for index in 0..<buffers.count { buffers[index].mDataByteSize = capacity }

    guard frames <= sink.renderBuffer.frameCapacity else {
      sink.renderDidFail(kAudio_ParamError)
      return kAudio_ParamError
    }
    let status = AudioUnitRender(unit, flags, timeStamp, bus, frames, list)
    guard status == noErr else {
      sink.renderDidFail(status)
      return status
    }
    sink.deliver(frames: AVAudioFrameCount(frames))
    return noErr
  }

  private static func check(_ step: String, _ status: OSStatus) throws {
    guard status != noErr else { return }
    throw AUHALError(step: step, status: status)
  }
}
