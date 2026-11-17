import Foundation

public struct TrackDrain: Equatable, Sendable {
  public let runs: [MeetingRun]
  public let freshRuns: Int
  public let droppedNanos: UInt64
  public let contendedNanos: UInt64

  public init(
    runs: [MeetingRun] = [], freshRuns: Int = 0, droppedNanos: UInt64 = 0,
    contendedNanos: UInt64 = 0
  ) {
    self.runs = runs
    self.freshRuns = freshRuns
    self.droppedNanos = droppedNanos
    self.contendedNanos = contendedNanos
  }

  public var peak: Int16 {
    var largest = 0
    for run in runs {
      for sample in run.samples { largest = max(largest, abs(Int(sample))) }
    }
    return Int16(min(largest, Int(Int16.max)))
  }
}

public final class TrackBuffer: @unchecked Sendable {
  public static let joinTolerance: UInt64 = 20_000_000
  public static let backlogSeconds: Double = 30
  public static let recordSlots = 4096
  public static let rates: ClosedRange<Double> = 8_000...384_000

  private struct Record {
    var start: UInt64
    var frames: Int
    var rate: Double
    var continues: Bool
  }

  private final class Half {
    let frames: UnsafeMutablePointer<Float>
    let capacity: Int
    let records: UnsafeMutablePointer<Record>
    var readPos = 0
    var writePos = 0
    var head = 0
    var count = 0
    var droppedNanos: UInt64 = 0
    var contendedNanos: UInt64 = 0

    init(capacity: Int) {
      self.capacity = capacity
      frames = .allocate(capacity: capacity)
      frames.initialize(repeating: 0, count: capacity)
      records = .allocate(capacity: TrackBuffer.recordSlots)
      records.initialize(
        repeating: Record(start: 0, frames: 0, rate: 0, continues: false),
        count: TrackBuffer.recordSlots)
    }

    deinit {
      frames.deallocate()
      records.deallocate()
    }

    func reset() {
      readPos = 0
      writePos = 0
      head = 0
      count = 0
      droppedNanos = 0
      contendedNanos = 0
    }

    func slot(_ i: Int) -> Int { (head + i) % TrackBuffer.recordSlots }

    func dropFrames(_ wanted: Int) {
      var left = wanted
      while left > 0 && count > 0 {
        let at = slot(0)
        let take = min(left, records[at].frames)
        records[at].start = HostTime.adding(
          records[at].start, TrackBuffer.nanos(take, records[at].rate))
        records[at].frames -= take
        records[at].continues = false
        readPos += take
        droppedNanos = HostTime.adding(droppedNanos, TrackBuffer.nanos(take, records[at].rate))
        left -= take
        if records[at].frames == 0 {
          head = (head + 1) % TrackBuffer.recordSlots
          count -= 1
        }
      }
    }
  }

  private let lock = NSLock()
  private let first: Half
  private let second: Half
  private var writingFirst = true
  private var rate: Double
  private var hasPrediction = false
  private var predictedNext: UInt64 = 0
  private var predictedRate: Double = 0
  private var calls = 0
  private var broken = false
  private var missedWrites = 0
  private var missedFrames = 0
  private var lastEnd: UInt64?

  private static func nanos(_ frames: Int, _ rate: Double) -> UInt64 {
    HostTime.nanos(Double(frames) / rate + 5e-10)
  }

  public init?(rate: Double) {
    guard Self.rates.contains(rate) else { return nil }
    self.rate = rate
    let capacity = Int(Self.backlogSeconds * rate)
    first = Half(capacity: capacity)
    second = Half(capacity: capacity)
  }

  public func setRate(_ rate: Double) {
    guard Self.rates.contains(rate) else { return }
    lock.lock()
    self.rate = rate
    lock.unlock()
  }

  public var callbacks: Int {
    lock.lock()
    defer { lock.unlock() }
    return calls
  }

  func holdingLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  var halves: (writing: UnsafeRawPointer, draining: UnsafeRawPointer) {
    holdingLock {
      let a = UnsafeRawPointer(first.frames)
      let b = UnsafeRawPointer(second.frames)
      return writingFirst ? (a, b) : (b, a)
    }
  }

  public func write(_ samples: UnsafeBufferPointer<Float>, hostNanos: UInt64) {
    let n = samples.count
    guard lock.try() else {
      missedWrites += 1
      missedFrames += n
      return
    }
    defer { lock.unlock() }
    let half = writingFirst ? first : second
    calls += 1 + missedWrites
    if missedWrites > 0 {
      half.contendedNanos = HostTime.adding(half.contendedNanos, Self.nanos(missedFrames, rate))
      broken = true
      missedWrites = 0
      missedFrames = 0
    }
    guard n > 0, let base = samples.baseAddress else { return }

    let distance =
      hostNanos >= predictedNext
      ? HostTime.elapsed(from: predictedNext, to: hostNanos)
      : HostTime.elapsed(from: hostNanos, to: predictedNext)
    let joins =
      hasPrediction && !broken && predictedRate == rate && distance <= Self.joinTolerance
    if joins && half.count > 0 {
      half.records[half.slot(half.count - 1)].frames += n
    } else {
      if half.count == Self.recordSlots { half.dropFrames(half.records[half.slot(0)].frames) }
      half.records[half.slot(half.count)] = Record(
        start: hostNanos, frames: n, rate: rate, continues: joins && half.count == 0)
      half.count += 1
    }
    broken = false
    let newest = half.records[half.slot(half.count - 1)]
    hasPrediction = true
    predictedRate = rate
    predictedNext = HostTime.adding(newest.start, Self.nanos(newest.frames, newest.rate))

    let skip = max(0, n - half.capacity)
    let kept = n - skip
    let at = (half.writePos + skip) % half.capacity
    let head = min(kept, half.capacity - at)
    (half.frames + at).update(from: base + skip, count: head)
    if kept > head { half.frames.update(from: base + skip + head, count: kept - head) }
    half.writePos += n
    let over = half.writePos - half.readPos - half.capacity
    if over > 0 { half.dropFrames(over) }
  }

  public func drain(resample: (UnsafeBufferPointer<Float>, Double) -> [Float]?) -> TrackDrain {
    lock.lock()
    let taken = writingFirst ? first : second
    writingFirst.toggle()
    (writingFirst ? first : second).reset()
    lock.unlock()

    var runs: [MeetingRun] = []
    var fresh = 0
    var dropped = taken.droppedNanos
    var position = taken.readPos
    for i in 0..<taken.count {
      let record = taken.records[taken.slot(i)]
      let frames = [Float](unsafeUninitializedCapacity: record.frames) { buffer, filled in
        let at = position % taken.capacity
        let head = min(record.frames, taken.capacity - at)
        buffer.baseAddress!.update(from: taken.frames + at, count: head)
        if record.frames > head {
          (buffer.baseAddress! + head).update(from: taken.frames, count: record.frames - head)
        }
        filled = record.frames
      }
      position += record.frames
      let carried = record.continues ? lastEnd : nil
      let start = carried ?? record.start
      lastEnd = HostTime.adding(start, Self.nanos(record.frames, record.rate))
      guard
        let converted = frames.withUnsafeBufferPointer({ resample($0, record.rate) })
      else {
        dropped = HostTime.adding(dropped, Self.nanos(record.frames, record.rate))
        continue
      }
      let run = MeetingRun(start: start, samples: converted.map(MeetingRun.sample))
      lastEnd = run.end
      if carried == nil { fresh += 1 }
      runs.append(run)
    }
    return TrackDrain(
      runs: runs, freshRuns: fresh, droppedNanos: dropped, contendedNanos: taken.contendedNanos)
  }
}
