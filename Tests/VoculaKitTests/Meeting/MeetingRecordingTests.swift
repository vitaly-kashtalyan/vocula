import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingRecordingTests {
  private let s: UInt64 = 1_000_000_000
  private let sample = MeetingRun.nanosPerSample
  private let cipher = MarkingCipher()

  private func recorded(seconds: UInt64 = 10) -> MeetingHeader {
    var header = MeetingHeader(
      id: UUID(), startedAt: Date(timeIntervalSinceReferenceDate: 0), anchor: s)
    header.finish(atHost: s + seconds * s, by: .stopped)
    return header
  }

  private func file(_ track: MeetingTrack, _ sequence: Int) -> String {
    "audio/\(track.rawValue)-\(String(format: "%06d", sequence)).sealed"
  }

  private func sealed(_ track: MeetingTrack, _ sequence: UInt32, _ runs: [MeetingRun]) -> Data {
    MarkingCipher.mark + MeetingChunk(track: track, sequence: sequence, runs: runs).encoded()
  }

  private func read(_ track: MeetingTrack, of header: MeetingHeader, _ chunks: [String: Data])
    async throws -> [Int16]
  {
    let root = meetingTemporaryDirectory()
    try plant(header: header, chunks: chunks, in: root)
    return try await MeetingRecording.track(
      track, of: header, in: MeetingStore(directory: root), cipher: cipher)
  }

  @Test func aTrackStartsAtTheAnchorWithItsGapsSilent() async throws {
    let header = recorded()
    let at = header.anchor + 3 * sample
    let samples = try await read(
      .mic, of: header,
      [
        file(.mic, 0): sealed(.mic, 0, [MeetingRun(start: at, samples: [1, 2])]),
        file(.mic, 1): sealed(.mic, 1, [MeetingRun(start: at + 4 * sample, samples: [3])]),
        file(.system, 0): sealed(.system, 0, [MeetingRun(start: at, samples: [9])]),
      ])
    #expect(samples == [0, 0, 0, 1, 2, 0, 0, 3])
  }

  @Test func overlappingAndOutOfOrderSamplesKeepWhatWasPlacedFirst() async throws {
    let header = recorded()
    let samples = try await read(
      .mic, of: header,
      [
        file(.mic, 0): sealed(.mic, 0, [MeetingRun(start: header.anchor, samples: [1, 2, 3, 4])]),
        file(.mic, 1): sealed(
          .mic, 1, [MeetingRun(start: header.anchor + 2 * sample, samples: [9, 9, 9])]),
        file(.mic, 2): sealed(.mic, 2, [MeetingRun(start: header.anchor, samples: [5, 5])]),
      ])
    #expect(samples == [1, 2, 3, 4, 9])
  }

  @Test func aTrackWithoutChunksIsEmpty() async throws {
    let header = recorded()
    let samples = try await read(
      .system, of: header,
      [file(.mic, 0): sealed(.mic, 0, [MeetingRun(start: header.anchor, samples: [1])])])
    #expect(samples.isEmpty)
  }

  @Test func anUnreadableChunkIsSkippedAndNoReadableChunkFails() async throws {
    let header = recorded()
    let good = sealed(.mic, 1, [MeetingRun(start: header.anchor + sample, samples: [4])])
    #expect(
      try await read(.mic, of: header, [file(.mic, 0): Data("garbage".utf8), file(.mic, 1): good])
        == [0, 4])
    await #expect(throws: MeetingStoreError.failed(step: "open", code: 0)) {
      try await read(.mic, of: header, [file(.mic, 0): Data("garbage".utf8)])
    }
  }

  @Test func aRunPastTheEndFails() async {
    let header = recorded(seconds: 1)
    await #expect(throws: MeetingStoreError.failed(step: "open", code: 0)) {
      try await read(
        .mic, of: header,
        [file(.mic, 0): sealed(.mic, 0, [MeetingRun(start: header.anchor + 5 * s, samples: [1])])])
    }
  }

  @Test func aMeetingWithoutAnEndCannotBeLaidOut() async {
    let header = MeetingHeader(
      id: UUID(), startedAt: Date(timeIntervalSinceReferenceDate: 0), anchor: s)
    await #expect(throws: MeetingStoreError.failed(step: "open", code: 0)) {
      try await read(
        .mic, of: header,
        [file(.mic, 0): sealed(.mic, 0, [MeetingRun(start: header.anchor, samples: [1])])])
    }
  }

  @Test func theMixAddsClampsAndPadsTheShorterTrack() {
    var mic: [Int16] = [10_000, -10_000, 1]
    MeetingRecording.mix([30_000, -30_000, 2, 5], into: &mic)
    #expect(mic == [32_767, -32_768, 3, 5])
    var longer: [Int16] = [1, 2, 3]
    MeetingRecording.mix([1], into: &longer)
    #expect(longer == [2, 2, 3])
  }

  @Test func theWAVIsSixteenKilohertzMonoSixteenBit() {
    let wav = [UInt8](MeetingRecording.wav([1, -2]))
    func number(at offset: Int, _ size: Int) -> Int {
      wav[offset..<offset + size].reversed().reduce(0) { $0 << 8 | Int($1) }
    }
    #expect(wav.count == 48)
    #expect(Array(wav[0..<4]) == Array("RIFF".utf8))
    #expect(number(at: 4, 4) == 40)
    #expect(Array(wav[8..<16]) == Array("WAVEfmt ".utf8))
    #expect(number(at: 20, 2) == 1)
    #expect(number(at: 22, 2) == 1)
    #expect(number(at: 24, 4) == 16_000)
    #expect(number(at: 28, 4) == 32_000)
    #expect(number(at: 34, 2) == 16)
    #expect(Array(wav[36..<40]) == Array("data".utf8))
    #expect(number(at: 40, 4) == 4)
    #expect(Array(wav[44...]) == [0x01, 0x00, 0xFE, 0xFF])
  }
}
