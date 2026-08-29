import Foundation

public enum AudioFormat {
  public static let sampleRate: Double = 16_000
  public static let channels: Int = 1
}

public enum PCMSamples {
  public static func rms(_ samples: ArraySlice<Float>) -> Float {
    guard !samples.isEmpty else { return 0 }
    let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
    return (sum / Float(samples.count)).squareRoot()
  }

  public static func displayLevel(_ level: Float) -> Double {
    let gated = Double(max(0, level - 0.004)) * 9
    return pow(min(1, gated), 0.6)
  }

  public static func peak(_ samples: [Float]) -> Float {
    samples.reduce(Float(0)) { max($0, abs($1)) }
  }

  public static func duration(sampleCount: Int) -> Duration {
    .milliseconds(Int(Double(sampleCount) / sampleRateMilliseconds))
  }

  public static func sampleCount(inLeading milliseconds: Int) -> Int {
    max(0, Int(Double(milliseconds) * sampleRateMilliseconds))
  }

  private static let sampleRateMilliseconds = AudioFormat.sampleRate / 1000

  public static func boostedIfQuiet(
    _ samples: [Float],
    gate: Float = 0.05,
    target: Float = 0.3,
    maxGain: Float = 50,
    ignoringLeading: Int = 0
  ) -> [Float] {
    let wholePeak = peak(samples)
    let judged =
      ignoringLeading < samples.count
      ? Array(samples[ignoringLeading...]) : samples
    let peak = peak(judged)
    guard peak > 0, wholePeak > 0, peak < gate else { return samples }
    let gain = min(target / peak, maxGain, 1 / wholePeak)
    guard gain > 1 else { return samples }
    return samples.map { $0 * gain }
  }
}

public final class AudioAccumulator: @unchecked Sendable {
  private let condition = NSCondition()
  private var accepting = false
  private var inFlight = 0
  private var samples: [Float] = []

  public init() {}

  public func reset() {
    condition.lock()
    precondition(inFlight == 0)
    samples.removeAll(keepingCapacity: true)
    accepting = true
    condition.unlock()
  }

  public func beginSlice() -> Bool {
    condition.lock()
    defer { condition.unlock() }
    guard accepting else { return false }
    inFlight += 1
    return true
  }

  public func finishSlice(_ slice: [Float]?) {
    condition.lock()
    if let slice { samples.append(contentsOf: slice) }
    inFlight -= 1
    precondition(inFlight >= 0)
    if inFlight == 0 { condition.broadcast() }
    condition.unlock()
  }

  public func closeAndTake() -> [Float] {
    closeAndTake(onAdmissionClosed: {})
  }

  func closeAndTake(onAdmissionClosed: () -> Void) -> [Float] {
    condition.lock()
    accepting = false
    onAdmissionClosed()
    while inFlight > 0 { condition.wait() }
    let result = samples
    samples = []
    condition.unlock()
    return result
  }
}

public protocol AudioRecording: AnyObject, Sendable {
  var isRunning: Bool { get async }
  func levelUpdates() -> AsyncStream<Float>
  func deviceChangeEvents() -> AsyncStream<Void>

  func start() async throws
  func stop() async -> [Float]
  func discard() async
}
