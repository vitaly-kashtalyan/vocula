import Dispatch
import Foundation
import Testing

@testable import VoculaKit

private final class LockedSamples: @unchecked Sendable {
  private let lock = NSLock()
  private var value: [Float] = []
  func set(_ samples: [Float]) { lock.withLock { value = samples } }
  func get() -> [Float] { lock.withLock { value } }
}

@Suite("Audio buffer")
struct AudioBufferTests {
  @Test("whisper's format is 16 kHz mono float32")
  func format() {
    #expect(AudioFormat.sampleRate == 16_000)
    #expect(AudioFormat.channels == 1)
  }

  @Test("RMS of silence is zero and of a constant signal is its magnitude")
  func rms() {
    #expect(PCMSamples.rms([0, 0, 0, 0][...]) == 0)
    #expect(abs(PCMSamples.rms([0.5, -0.5, 0.5, -0.5][...]) - 0.5) < 0.0001)
  }

  @Test("an empty buffer has zero level rather than NaN")
  func emptyRMS() {
    #expect(PCMSamples.rms([Float]()[...]) == 0)
  }

  @Test("seconds are computed from the sample rate")
  func duration() {
    #expect(PCMSamples.duration(sampleCount: 32_000) == .seconds(2))
  }

  private func peak(_ samples: [Float]) -> Float {
    samples.reduce(Float(0)) { max($0, abs($1)) }
  }

  @Test("a recording at speaking level is handed on untouched")
  func boostLeavesNormalSpeechAlone() {
    let normal: [Float] = [0.4, -0.62, 0.05, 0, -0.31]
    #expect(PCMSamples.boostedIfQuiet(normal) == normal)
  }

  @Test("the gate is a floor, not a target: a buffer AT the gate is untouched")
  func boostGateBoundary() {
    let atGate: [Float] = [0.05, -0.02]
    #expect(PCMSamples.boostedIfQuiet(atGate) == atGate)
    let below: [Float] = [0.0499, -0.02]
    #expect(PCMSamples.boostedIfQuiet(below) != below)
  }

  @Test("a quiet recording is lifted to the target peak")
  func boostLiftsQuietToTarget() {
    let quiet: [Float] = [0.01, -0.005, 0, 0.0025]
    let boosted = PCMSamples.boostedIfQuiet(quiet)
    #expect(abs(peak(boosted) - 0.3) < 0.0001)
    #expect(abs(boosted[1] / boosted[0] - quiet[1] / quiet[0]) < 0.0001)
    #expect(boosted[2] == 0)
  }

  @Test("the gain is capped, so a near-empty room is not amplified 3000x")
  func boostCapsGain() {
    let hiss: [Float] = [0.0001, -0.00005]
    let boosted = PCMSamples.boostedIfQuiet(hiss)
    #expect(abs(peak(boosted) - 0.005) < 0.000001)
    #expect(peak(boosted) < 0.3)
  }

  @Test("digital silence stays silence rather than becoming NaN")
  func boostOfSilence() {
    let silence = [Float](repeating: 0, count: 16)
    let boosted = PCMSamples.boostedIfQuiet(silence)
    #expect(boosted == silence)
    #expect(boosted.allSatisfy { $0.isFinite })
    #expect(PCMSamples.boostedIfQuiet([]).isEmpty)
  }

  @Test("boosting never clips, at any input level")
  func boostNeverClips() {
    for peakLevel in [Float(0.0001), 0.001, 0.005, 0.02, 0.049, 0.05, 0.5, 1.0] {
      let buffer: [Float] = [peakLevel, -peakLevel, peakLevel / 2]
      let boosted = PCMSamples.boostedIfQuiet(buffer)
      #expect(
        peak(boosted) <= max(0.3, peakLevel) + 0.0001,
        "clipped at input peak \(peakLevel)")
    }
  }

  @Test("taking a recording returns slices in order and clears the buffer")
  func accumulatorTakesAndClears() {
    let buffer = AudioAccumulator()
    buffer.reset()
    #expect(buffer.beginSlice())
    buffer.finishSlice([1, 2])
    #expect(buffer.beginSlice())
    buffer.finishSlice([3])
    #expect(buffer.closeAndTake() == [1, 2, 3])
    #expect(buffer.closeAndTake().isEmpty)
  }

  @Test("a closed recording rejects callbacks from the next hardware turn")
  func accumulatorRejectsLateCallbacks() {
    let buffer = AudioAccumulator()
    buffer.reset()
    _ = buffer.closeAndTake()
    #expect(buffer.beginSlice() == false)
  }

  @Test("each subscriber gets its own stream, and one ending does not end the source")
  func fanoutSurvivesASubscriberEnding() async {
    let fanout = StreamFanout<Int>()
    let first = fanout.subscribe()
    let firstTask = Task { await first.first { _ in true } }
    fanout.emit(1)
    #expect(await firstTask.value == 1)

    let second = fanout.subscribe()
    let secondTask = Task { await second.first { _ in true } }
    fanout.emit(2)
    #expect(await secondTask.value == 2)
  }

  @Test("a cancelled subscriber is dropped and stops costing anything")
  func fanoutDropsCancelledSubscribers() async {
    let fanout = StreamFanout<Int>()
    let stream = fanout.subscribe()
    #expect(fanout.subscriberCount == 1)
    let task = Task { for await _ in stream {} }
    task.cancel()
    _ = await task.value
    for _ in 0..<100 where fanout.subscriberCount != 0 {
      try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(fanout.subscriberCount == 0)
    fanout.emit(1)
  }

  @Test("finishAll leaves no consumer, and the fan-out still serves the next one")
  func fanoutSurvivesTeardownAndRestart() async {
    let fanout = StreamFanout<Int>(bufferingPolicy: .unbounded)
    let first = fanout.subscribe()
    #expect(fanout.subscriberCount == 1)
    fanout.finishAll()
    var afterTeardown = 0
    for await _ in first { afterTeardown += 1 }
    #expect(afterTeardown == 0)
    #expect(fanout.subscriberCount == 0)

    let second = fanout.subscribe()
    #expect(fanout.subscriberCount == 1)
    fanout.emit(1)
    fanout.emit(2)
    fanout.finishAll()
    var received: [Int] = []
    for await value in second { received.append(value) }
    #expect(received == [1, 2])
  }

  @Test("close waits for a conversion that already entered the callback")
  func closeWaitsForInFlightSlice() {
    let buffer = AudioAccumulator()
    buffer.reset()
    #expect(buffer.beginSlice())
    let admissionClosed = DispatchSemaphore(value: 0)
    let returnedFromClose = DispatchSemaphore(value: 0)
    let taken = LockedSamples()
    DispatchQueue.global().async {
      taken.set(buffer.closeAndTake(onAdmissionClosed: { admissionClosed.signal() }))
      returnedFromClose.signal()
    }
    admissionClosed.wait()
    #expect(returnedFromClose.wait(timeout: .now() + 0.05) == .timedOut)
    buffer.finishSlice([1])
    #expect(returnedFromClose.wait(timeout: .now() + 1) == .success)
    #expect(taken.get() == [1])
  }
}

@Suite("The start cue must not defeat the quiet boost")
struct QuietBoostCueTests {
  private let cueSamples = PCMSamples.sampleCount(inLeading: 600)

  private func buffer(cuePeak: Float, speechPeak: Float) -> [Float] {
    Array(repeating: cuePeak, count: cueSamples)
      + Array(repeating: speechPeak, count: 16_000)
  }

  @Test("a loud cue no longer suppresses the boost for quiet speech")
  func cueDoesNotSuppressTheBoost() {
    let samples = buffer(cuePeak: 0.06, speechPeak: 0.004)
    #expect(
      PCMSamples.boostedIfQuiet(samples) == samples,
      "whole-buffer judgement is unchanged and still sees the cue")
    let boosted = PCMSamples.boostedIfQuiet(samples, ignoringLeading: cueSamples)
    #expect(boosted != samples)
    #expect(
      PCMSamples.peak(Array(boosted[cueSamples...])) > 0.05,
      "the speech must land inside the band the pipeline is measured to work in")
  }

  @Test("boosting still cannot clip, however loud the cue is")
  func boostingCannotClip() {
    for cuePeak in [Float(0.06), 0.2, 0.5, 0.9] {
      let boosted = PCMSamples.boostedIfQuiet(
        buffer(cuePeak: cuePeak, speechPeak: 0.004),
        ignoringLeading: cueSamples)
      #expect(
        PCMSamples.peak(boosted) <= 1.0,
        "a cue at \(cuePeak) was amplified past full scale")
    }
  }

  @Test("a buffer shorter than the cue falls back to judging all of it")
  func shorterThanTheCue() {
    let quiet = [Float](repeating: 0.004, count: 100)
    #expect(
      PCMSamples.boostedIfQuiet(quiet, ignoringLeading: cueSamples)
        == PCMSamples.boostedIfQuiet(quiet))
  }

  @Test("an ordinary recording behind a cue is still untouched")
  func ordinarySpeechUntouched() {
    let samples = buffer(cuePeak: 0.06, speechPeak: 0.4)
    #expect(PCMSamples.boostedIfQuiet(samples, ignoringLeading: cueSamples) == samples)
  }
}
