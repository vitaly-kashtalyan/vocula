import Foundation

public enum MeetingRecording {
  public static let sampleRate = 16_000

  public static func track(
    _ track: MeetingTrack, of header: MeetingHeader, in store: MeetingStore,
    cipher: any HistoryCipher
  ) async throws -> [Int16] {
    guard let end = header.endHost else { throw MeetingStoreError.failed(step: "open", code: 0) }
    let names = try await store.chunkNames(of: header.id, track: track)
    var windows = MeetingTrackWindows(anchor: header.anchor, end: end)
    var out: [Int16] = []
    if !names.isEmpty {
      out.reserveCapacity(
        MeetingTimeline.offset(of: end, anchor: header.anchor) + MeetingTrackWindows.endSlack)
    }
    var opened = 0
    for name in names {
      try Task.checkCancellation()
      guard
        let chunk = try await store.readChunk(
          of: header.id, track: track, name: name, cipher: cipher)
      else { continue }
      opened += 1
      do { try windows.add(chunk) } catch { throw MeetingStoreError.failed(step: "open", code: 0) }
      while let window = windows.next(final: false) { out += window.samples }
    }
    guard names.isEmpty || opened > 0 else { throw MeetingStoreError.failed(step: "open", code: 0) }
    while let window = windows.next(final: true) { out += window.samples }
    return out
  }

  public static func mix(_ other: [Int16], into track: inout [Int16]) {
    if track.count < other.count {
      track.append(contentsOf: repeatElement(0, count: other.count - track.count))
    }
    for (index, sample) in other.enumerated() {
      track[index] = Int16(clamping: Int32(track[index]) + Int32(sample))
    }
  }

  public static func wav(_ samples: [Int16]) -> Data {
    let bytes = UInt32(min(samples.count, (Int(UInt32.max) - 36) / 2) * 2)
    var data = Data(capacity: 44 + Int(bytes))
    func put<T: FixedWidthInteger>(_ value: T) {
      withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    data.append(contentsOf: Array("RIFF".utf8))
    put(bytes + 36)
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    put(UInt32(16))
    put(UInt16(1))
    put(UInt16(1))
    put(UInt32(sampleRate))
    put(UInt32(sampleRate * 2))
    put(UInt16(2))
    put(UInt16(16))
    data.append(contentsOf: Array("data".utf8))
    put(bytes)
    samples.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      data.append(base.assumingMemoryBound(to: UInt8.self), count: Int(bytes))
    }
    return data
  }
}
