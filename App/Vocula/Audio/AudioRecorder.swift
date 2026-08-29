import AVFoundation
import VoculaKit

enum AudioRecorderError: LocalizedError, CustomNSError {
  case engineDidNotStart(Error)
  case noInputDevice
  case interruptedAudioPending

  static let errorDomain = "Vocula.AudioRecorderError"

  var errorCode: Int {
    switch self {
    case .engineDidNotStart: return 1
    case .noInputDevice: return 2
    case .interruptedAudioPending: return 3
    }
  }

  var errorUserInfo: [String: Any] {
    if case .engineDidNotStart(let underlying) = self {
      return [NSUnderlyingErrorKey: underlying]
    }
    return [:]
  }

  var errorDescription: String? {
    switch self {
    case .noInputDevice:
      return String(
        localized: "audio.noInputDevice",
        defaultValue:
          "No microphone is connected, so there was nothing to record from. Connect one, then try again.",
        comment: "Refusal shown when no input device exists at all.")
    case .interruptedAudioPending:
      return String(
        localized: "audio.interruptedAudioPending",
        defaultValue:
          "The last recording is still being closed after the audio device changed. Press the key again in a moment.",
        comment: "Refusal shown while a previous session is still tearing down.")
    case .engineDidNotStart:
      return String(
        localized: "audio.engineDidNotStart",
        defaultValue:
          "The microphone could not be opened. Check that it is connected and not in use by another app, then try again.",
        comment: "Refusal shown when the capture unit refused to start.")
    }
  }
}

actor AudioRecorder: AudioRecording {
  private final class ConverterInput: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var consumed = false

    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func take(_ inputStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>)
      -> AVAudioBuffer?
    {
      lock.lock()
      defer { lock.unlock() }
      guard !consumed else {
        inputStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      inputStatus.pointee = .haveData
      return buffer
    }
  }

  private let accumulator = AudioAccumulator()
  private var unit: AUHALInputUnit?
  private var monitor: AudioDeviceMonitor?
  private var openGeneration = 0

  private let bufferCounter = BufferCounter()
  private var livenessTask: Task<Void, Never>?

  private var running = false

  private let levelFanout = StreamFanout<Float>()
  private let deviceFanout = StreamFanout<Void>()
  nonisolated func levelUpdates() -> AsyncStream<Float> { levelFanout.subscribe() }
  nonisolated func deviceChangeEvents() -> AsyncStream<Void> { deviceFanout.subscribe() }
  var isRunning: Bool { running }

  init() {}

  deinit {
    levelFanout.finishAll()
    deviceFanout.finishAll()
  }

  func start() async throws {
    guard !running else { return }
    guard interrupted == nil else { throw AudioRecorderError.interruptedAudioPending }
    accumulator.reset()
    bufferCounter.reset()
    failedOver = 0
    openGeneration += 1

    let priority = AppSettings().microphonePriority
    let connected = AudioInputDevices.all
    if let top = priority.devices.first, !connected.contains(where: { $0.uid == top.uid }) {
      diagnose?("audio.deviceMissing", "")
    }
    let ranked = priority.firstAvailable(in: Set(connected.map(\.uid)))
      .flatMap { chosen in connected.first { $0.uid == chosen.uid }?.id }
    guard let device = ranked ?? AudioInputDevices.builtInID else {
      _ = accumulator.closeAndTake()
      throw AudioRecorderError.noInputDevice
    }
    do {
      try openUnit(
        on: device,
        uid: connected.first { $0.id == device }?.uid,
        generation: openGeneration)
    } catch {
      _ = accumulator.closeAndTake()
      throw error
    }
  }

  private func openUnit(on device: AudioDeviceID, uid: String?, generation: Int) throws {
    guard let hardware = AUHALInputUnit.hardwareFormat(of: device),
      let client = CaptureFormat.client(
        hardwareRate: hardware.rate,
        hardwareChannels: hardware.channels)
    else { throw AudioRecorderError.noInputDevice }

    let frames = AUHALInputUnit.bufferFrameSize(of: device)
    guard
      let sink = CaptureSink(
        clientFormat: client,
        frameCapacity: frames,
        accumulator: accumulator,
        levels: levelFanout,
        counter: bufferCounter,
        diagnose: diagnose)
    else { throw AudioRecorderError.noInputDevice }

    do {
      let opened = try AUHALInputUnit(deviceID: device, sink: sink, maximumFrames: frames)
      try opened.start()
      unit = opened
    } catch let failure as AUHALError {
      diagnose?(
        "audio.startFailed",
        "step=\(failure.step) code=\(failure.status)"
          + " wanted=\(device) rate=\(Int(client.rate))"
          + " default=\(AudioInputDevices.systemDefaultID.map(String.init) ?? "none")")
      throw AudioRecorderError.engineDidNotStart(failure.asNSError)
    }

    openDeviceUID = uid
    running = true
    if unit?.heldDeviceID != device {
      diagnose?("audio.deviceRefused", "wanted=\(device)")
    }
    startDeviceMonitor(on: device, openedRate: client.rate, generation: generation)
    startLivenessWatch(generation: generation)
  }

  private func startDeviceMonitor(
    on device: AudioDeviceID,
    openedRate: Double,
    generation: Int
  ) {
    monitor?.stop()
    monitor = AudioDeviceMonitor(
      device: device,
      openedRate: openedRate,
      diagnose: diagnose
    ) { [weak self] lost in
      Task { await self?.deviceWasLost(lost, generation: generation) }
    }
  }

  private func deviceWasLost(_ device: AudioDeviceID, generation: Int) {
    guard running, generation == openGeneration else { return }
    diagnose?("audio.deviceLost", "wanted=\(device)")
    guard !failOver() else { return }
    tearDownAfterDeviceChange()
  }

  private func failOver() -> Bool {
    guard let lost = openDeviceUID else { return false }
    let connected = AudioInputDevices.all
    guard
      let chosen = DeviceFailover.next(
        after: lost,
        priority: AppSettings().microphonePriority,
        connected: Set(connected.map(\.uid)),
        alreadyFailedOver: failedOver),
      let device = connected.first(where: { $0.uid == chosen.uid })?.id
    else { return false }

    closeUnit()
    bufferCounter.reset()
    failedOver += 1
    openGeneration += 1
    do {
      try openUnit(on: device, uid: chosen.uid, generation: openGeneration)
    } catch {
      return false
    }
    diagnose?("audio.failover", "wanted=\(device) count=\(failedOver)")
    return true
  }

  private func startLivenessWatch(generation: Int) {
    livenessTask?.cancel()
    let counter = bufferCounter
    livenessTask = Task { [weak self] in
      var watchdog = InputLivenessWatchdog()
      while !Task.isCancelled {
        try? await Task.sleep(for: InputLivenessWatchdog.checkInterval)
        guard !Task.isCancelled, let self, await self.isRunning else { return }
        guard watchdog.check(buffersDelivered: counter.value) == .dead else { continue }
        await self.inputWentSilent(generation: generation)
      }
    }
  }

  private func inputWentSilent(generation: Int) {
    guard running, generation == openGeneration else { return }
    diagnose?("audio.inputWentSilent", "")
    tearDownAfterDeviceChange()
  }

  @discardableResult
  func prewarm() -> (rate: Int, channels: Int) {
    guard
      let device = AudioInputDevices.resolvedDeviceID(
        for: AppSettings().microphonePriority),
      let format = AUHALInputUnit.hardwareFormat(of: device)
    else { return (0, 0) }
    return (Int(format.rate), format.channels)
  }

  private var diagnose: (@Sendable (String, String) -> Void)?

  func setDiagnose(_ diagnose: @escaping @Sendable (String, String) -> Void) {
    self.diagnose = diagnose
  }

  func stop() async -> [Float] {
    if let interrupted {
      self.interrupted = nil
      return interrupted
    }
    guard running else { return [] }
    closeUnit()
    running = false
    return accumulator.closeAndTake()
  }

  private func closeUnit() {
    livenessTask?.cancel()
    livenessTask = nil
    monitor?.stop()
    monitor = nil
    unit?.stop()
    unit = nil
  }

  func discard() async {
    interrupted = nil
    if running { _ = await stop() }
  }

  nonisolated static func makeConverter(
    from source: AVAudioFormat,
    to target: AVAudioFormat
  ) -> AVAudioConverter? {
    guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
    if source.channelCount > 1 { converter.channelMap = [0] }
    return converter
  }

  nonisolated static func convert(
    _ buffer: AVAudioPCMBuffer,
    with converter: AVAudioConverter,
    to target: AVAudioFormat
  ) -> [Float]? {
    let ratio = target.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
    guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)
    else { return nil }

    let input = ConverterInput(buffer)
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, inputStatus in
      input.take(inputStatus)
    }
    guard status != .error, error == nil,
      let channel = output.floatChannelData?[0], output.frameLength > 0
    else { return nil }
    return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
  }

  private func tearDownAfterDeviceChange() {
    closeUnit()
    running = false
    interrupted = accumulator.closeAndTake()
    deviceFanout.emit(())
  }

  private var interrupted: [Float]?
  private var openDeviceUID: String?
  private var failedOver = 0
}
