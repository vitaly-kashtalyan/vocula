import Foundation
import Testing

@testable import VoculaKit

private let ms: UInt64 = 1_000_000
private let s: UInt64 = 1_000_000_000
private let identity: @Sendable (UnsafeBufferPointer<Float>, Double) -> [Float]? = { samples, _ in
  Array(samples)
}

private func write(_ b: TrackBuffer, frames: Int, value: Float = 0, at: UInt64) {
  let data = [Float](repeating: value, count: frames)
  data.withUnsafeBufferPointer { b.write($0, hostNanos: at) }
}

private func buffer(_ rate: Double = 16_000) -> TrackBuffer { TrackBuffer(rate: rate)! }

@Suite struct TrackBufferTests {
  @Test func aBufferWithin20msExtendsTheRun() {
    let b = buffer()
    write(b, frames: 160, at: 0)
    write(b, frames: 160, at: 29 * ms)
    let d = b.drain(resample: identity)
    #expect(d.runs.count == 1)
    #expect(d.runs[0].samples.count == 320)
    #expect(d.freshRuns == 1)
  }

  @Test func aBufferPast20msStartsANewRun() {
    let b = buffer()
    write(b, frames: 160, at: 0)
    write(b, frames: 160, at: 31 * ms)
    let d = b.drain(resample: identity)
    #expect(d.runs.map(\.start) == [0, 31 * ms])
    #expect(d.freshRuns == 2)
  }

  @Test func anEarlyBufferWithin20msExtends() {
    let b = buffer()
    write(b, frames: 160, at: 0)
    write(b, frames: 160, at: 0)
    #expect(b.drain(resample: identity).runs.map(\.samples.count) == [320])
  }

  @Test func aHostTimeBeforeThePredictionDoesNotTrap() {
    let b = buffer()
    write(b, frames: 160, at: s)
    write(b, frames: 160, at: 0)
    #expect(b.drain(resample: identity).runs.map(\.start) == [s, 0])
  }

  @Test func aDrainBoundaryIsSeamless() {
    let b = buffer()
    write(b, frames: 160, at: 0)
    _ = b.drain(resample: identity)
    write(b, frames: 160, at: 10 * ms)
    let second = b.drain(resample: identity)
    #expect(second.runs[0].start == 10 * ms)
    #expect(second.freshRuns == 0)
  }

  @Test func aRateChangeStartsANewRun() {
    let b = buffer()
    write(b, frames: 160, at: 0)
    b.setRate(48_000)
    write(b, frames: 480, at: 10 * ms)
    var rates: [Double] = []
    let d = b.drain { samples, rate in
      rates.append(rate)
      return Array(samples)
    }
    #expect(d.runs.count == 2)
    #expect(rates == [16_000, 48_000])
  }

  @Test func anInvalidRateIsRefused() {
    for bad in [0, 7_999, 384_001, .nan, .infinity] as [Double] {
      #expect(TrackBuffer(rate: bad) == nil)
    }
    #expect(TrackBuffer(rate: 8_000) != nil)
    #expect(TrackBuffer(rate: 384_000) != nil)
    let b = buffer()
    write(b, frames: 160, at: 0)
    b.setRate(.nan)
    b.setRate(1_000_000)
    write(b, frames: 160, at: 10 * ms)
    #expect(b.drain(resample: identity).runs.map(\.samples.count) == [320])
  }

  @Test func theBacklogKeepsTheNewestThirtySeconds() {
    let b = buffer(8_000)
    for k in 0..<40 { write(b, frames: 8_000, at: UInt64(k) * s) }
    let d = b.drain(resample: identity)
    #expect(d.runs.count == 1)
    #expect(d.runs[0].samples.count == 240_000)
    #expect(d.runs[0].start == 10 * s)
    #expect(d.droppedNanos == 10 * s)
  }

  @Test func aFullRecordRingDropsTheOldest() {
    let b = buffer()
    for k in 0..<4_097 { write(b, frames: 100, at: UInt64(k) * 100 * ms) }
    let d = b.drain(resample: identity)
    #expect(d.runs.count == 4_096)
    #expect(d.runs[0].start == 100 * ms)
    #expect(d.droppedNanos == 6_250_000)
  }

  @Test func aFailedResampleIsDropped() {
    let b = buffer()
    write(b, frames: 160, at: 0)
    let d = b.drain { _, _ in nil }
    #expect(d.runs.isEmpty)
    #expect(d.droppedNanos == 10 * ms)
  }

  @Test func callbacksAreCounted() {
    let b = buffer()
    for k in 0..<3 { write(b, frames: 160, at: UInt64(k) * 10 * ms) }
    #expect(b.callbacks == 3)
  }

  @Test func peakIsTheLargestMagnitude() {
    let b = buffer()
    let data: [Float] = [0.1, -0.5]
    data.withUnsafeBufferPointer { b.write($0, hostNanos: 0) }
    #expect(b.drain(resample: identity).peak == 16384)
  }

  @Test func aContendedWriteIsDroppedNotWaitedFor() {
    let b = buffer()
    write(b, frames: 160, at: 0)
    b.holdingLock { write(b, frames: 160, at: 10 * ms) }
    write(b, frames: 160, at: 20 * ms)
    let d = b.drain(resample: identity)
    #expect(d.runs.map(\.start) == [0, 20 * ms])
    #expect(d.runs.map(\.samples.count) == [160, 160])
    #expect(d.contendedNanos == 10 * ms)
    #expect(d.droppedNanos == 0)
    #expect(d.freshRuns == 2)
    #expect(b.callbacks == 3)
  }

  @Test func theSwapExchangesTheHalves() {
    let b = buffer()
    let h = b.halves
    write(b, frames: 160, value: 0.5, at: 0)
    _ = b.drain(resample: identity)
    #expect(b.halves.writing == h.draining)
    #expect(b.halves.draining == h.writing)
    write(b, frames: 160, value: 0.25, at: 10 * ms)
    let d = b.drain(resample: identity)
    #expect(b.halves.writing == h.writing)
    #expect(d.runs.count == 1)
    #expect(d.runs[0].samples.allSatisfy { $0 == MeetingRun.sample(0.25) })
  }

  @Test("LIMIT: allocation-freedom on the audio thread is reviewed, not measured")
  func anAllocationInsideAWriteGoesUnseen() {
    let plain = buffer()
    let allocating = buffer()
    let data = [Float](repeating: 0.1, count: 160)
    for k in 0..<100 {
      data.withUnsafeBufferPointer { plain.write($0, hostNanos: UInt64(k) * 10 * ms) }
      data.withUnsafeBufferPointer {
        _ = Array($0)
        allocating.write($0, hostNanos: UInt64(k) * 10 * ms)
      }
    }
    #expect(plain.drain(resample: identity) == allocating.drain(resample: identity))
  }

  @Test("LIMIT: after a rate rise the backlog holds fewer than thirty seconds")
  func aRateRiseShortensTheBacklog() {
    let b = buffer(8_000)
    b.setRate(16_000)
    for k in 0..<40 { write(b, frames: 16_000, at: UInt64(k) * s) }
    let d = b.drain(resample: identity)
    #expect(d.runs.count == 1)
    #expect(d.runs[0].samples.count == 240_000)
    #expect(d.runs[0].start == 25 * s)
    #expect(d.droppedNanos == 25 * s)
  }
}
