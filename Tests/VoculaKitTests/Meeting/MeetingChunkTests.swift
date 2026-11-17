import Foundation
import Testing

@testable import VoculaKit

struct MeetingChunkTests {
  private let sample = MeetingChunk(
    track: .mic, sequence: 42,
    runs: [
      MeetingRun(start: 3_000_000_000, samples: [0, .max, -32767, -1]),
      MeetingRun(start: 9_000_000_000, samples: []),
    ])

  @Test func aChunkRoundTrips() throws {
    #expect(try MeetingChunk(decoding: sample.encoded()) == sample)
  }

  @Test func theLayoutIsPinned() {
    let bytes = [UInt8](
      MeetingChunk(track: .system, sequence: 7, runs: [MeetingRun(start: 1, samples: [1, -1])])
        .encoded())
    #expect(
      bytes
        == Array("VMC1".utf8) + [
          1, 7, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0xFF, 0xFF,
        ])
  }

  @Test func everyTruncationThrows() {
    let bytes = [UInt8](sample.encoded())
    for n in 0..<bytes.count {
      #expect(throws: MeetingChunk.DecodeError.self) {
        try MeetingChunk(decoding: Data(bytes.prefix(n)))
      }
    }
  }

  @Test func garbageThrows() {
    let good = [UInt8](sample.encoded())
    var badMagic = good
    badMagic[0] = 0x58
    var badTrack = good
    badTrack[4] = 2
    let trailing = good + [0]
    var hugeCount = [UInt8](
      MeetingChunk(track: .mic, sequence: 0, runs: [MeetingRun(start: 0, samples: [])]).encoded())
    hugeCount.replaceSubrange(21..<25, with: [0xFF, 0xFF, 0xFF, 0xFF])
    for bad in [badMagic, badTrack, trailing, hugeCount] {
      #expect(throws: MeetingChunk.DecodeError.self) { try MeetingChunk(decoding: Data(bad)) }
    }
  }

  @Test func samplesAreClampedToSixteenBits() {
    #expect(MeetingRun.sample(2) == 32767)
    #expect(MeetingRun.sample(-2) == -32767)
    #expect(MeetingRun.sample(0.5) == 16384)
    #expect(MeetingRun.sample(.nan) == 0)
    #expect(MeetingRun.sample(.infinity) == 32767)
  }

  @Test func aRunEndsWhereItsNextSampleFalls() {
    #expect(MeetingRun(start: 10, samples: [0, 0]).end == 125_010)
  }

  @Test func aRunNearTheEndOfTimeDoesNotTrap() {
    #expect(MeetingRun(start: .max - 10, samples: [0]).end == .max)
  }
}
