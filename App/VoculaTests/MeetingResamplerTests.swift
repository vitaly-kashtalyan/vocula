import Foundation
import Testing
import VoculaKit

@testable import Vocula

@Suite struct MeetingResamplerTests {
  @Test func aDrainIsResampledTo16kHz() throws {
    let buffer = try #require(TrackBuffer(rate: 48_000))
    let tone = [Float](repeating: 0.5, count: 4_800)
    tone.withUnsafeBufferPointer { buffer.write($0, hostNanos: 1_000_000_000) }
    let runs = MeetingResampler().drain(buffer).runs
    #expect(runs.map(\.start) == [1_000_000_000])
    let samples = runs.first?.samples ?? []
    #expect((1_200...1_600).contains(samples.count))
    let middle = Int(samples.isEmpty ? 0 : samples[samples.count / 2])
    #expect(abs(middle - Int(MeetingRun.sample(0.5))) < 164)
  }
}
