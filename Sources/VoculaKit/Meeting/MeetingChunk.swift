import Foundation

public struct MeetingRun: Equatable, Sendable {
  public static let nanosPerSample: UInt64 = 62_500

  public let start: UInt64
  public let samples: [Int16]

  public var end: UInt64 {
    HostTime.adding(start, UInt64(samples.count) * Self.nanosPerSample)
  }

  public init(start: UInt64, samples: [Int16]) {
    self.start = start
    self.samples = samples
  }

  public static func sample(_ value: Float) -> Int16 {
    guard !value.isNaN else { return 0 }
    return Int16((min(max(value, -1), 1) * 32767).rounded())
  }
}

public struct MeetingChunk: Equatable, Sendable {
  public enum DecodeError: Error { case malformed }

  private static let magic = Array("VMC1".utf8)

  public let track: MeetingTrack
  public let sequence: UInt32
  public let runs: [MeetingRun]

  public init(track: MeetingTrack, sequence: UInt32, runs: [MeetingRun]) {
    self.track = track
    self.sequence = sequence
    self.runs = runs
  }

  public init(decoding data: Data) throws {
    let bytes = [UInt8](data)
    var at = 0
    func take(_ n: Int) throws -> ArraySlice<UInt8> {
      guard n >= 0, n <= bytes.count - at else { throw DecodeError.malformed }
      defer { at += n }
      return bytes[at..<at + n]
    }
    func integer<T: FixedWidthInteger>(_: T.Type) throws -> T {
      try take(MemoryLayout<T>.size).reversed().reduce(0) { $0 << 8 | T($1) }
    }
    guard try Array(take(4)) == Self.magic else { throw DecodeError.malformed }
    switch try integer(UInt8.self) {
    case 0: track = .mic
    case 1: track = .system
    default: throw DecodeError.malformed
    }
    sequence = try integer(UInt32.self)
    let count = try integer(UInt32.self)
    guard count > 0 else { throw DecodeError.malformed }
    var runs: [MeetingRun] = []
    for _ in 0..<count {
      let start = try integer(UInt64.self)
      let n = Int(try integer(UInt32.self))
      guard n <= (bytes.count - at) / 2 else { throw DecodeError.malformed }
      var samples: [Int16] = []
      samples.reserveCapacity(n)
      for _ in 0..<n { samples.append(Int16(bitPattern: try integer(UInt16.self))) }
      runs.append(MeetingRun(start: start, samples: samples))
    }
    guard at == bytes.count else { throw DecodeError.malformed }
    self.runs = runs
  }

  public func encoded() -> Data {
    var out = Self.magic
    func put<T: FixedWidthInteger>(_ value: T) {
      withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) }
    }
    switch track {
    case .mic: put(UInt8(0))
    case .system: put(UInt8(1))
    }
    put(sequence)
    put(UInt32(runs.count))
    for run in runs {
      put(run.start)
      put(UInt32(run.samples.count))
      for s in run.samples { put(s) }
    }
    return Data(out)
  }
}
