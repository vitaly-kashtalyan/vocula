import Foundation
import Testing

@testable import VoculaKit

private func segment(_ from: Int, _ to: Int, _ probability: Float = 0.9) -> SpeechSegment {
  SpeechSegment(start: .milliseconds(from), end: .milliseconds(to), probability: probability)
}

@Suite("Speech markup")
struct SpeechMarkupTests {
  @Test("no segments means no speech")
  func noSegments() {
    let markup = SpeechMarkup(
      segments: [], totalDuration: .seconds(10),
      thresholds: .default)
    #expect(markup.hasSpeech == false)
    #expect(markup.metrics.segmentCount == 0)
    #expect(markup.metrics.speechFraction == 0)
  }

  @Test("a single short burst inside a long silence is not speech")
  func singleBurstInLongSilence() {
    let markup = SpeechMarkup(
      segments: [segment(60_000, 60_120)],
      totalDuration: .seconds(120), thresholds: .default)
    #expect(markup.hasSpeech == false)
  }

  @Test("a normal phrase is speech")
  func normalPhrase() {
    let markup = SpeechMarkup(
      segments: [segment(200, 2_400)],
      totalDuration: .milliseconds(2_600), thresholds: .default)
    #expect(markup.hasSpeech == true)
    #expect(markup.metrics.segmentCount == 1)
    #expect(markup.metrics.speechFraction > 0.8)
  }

  @Test("segments below the probability floor do not count")
  func lowProbabilityIgnored() {
    let markup = SpeechMarkup(
      segments: [segment(0, 2_000, 0.1)],
      totalDuration: .milliseconds(2_100), thresholds: .default)
    #expect(markup.hasSpeech == false)
  }

  @Test("metrics are Codable and survive a round trip")
  func metricsAreCodable() throws {
    let markup = SpeechMarkup(
      segments: [segment(0, 1_000), segment(1_500, 2_000)],
      totalDuration: .seconds(3), thresholds: .default)
    let data = try JSONEncoder().encode(markup.metrics)
    let decoded = try JSONDecoder().decode(SpeechMetrics.self, from: data)
    #expect(decoded == markup.metrics)
    #expect(decoded.segmentCount == 2)
  }

  @Test("no segment but a live frame sends the whole buffer")
  func salvageOnLiveFrames() {
    var probabilities = [Float](repeating: 0.01, count: 47)
    probabilities[25] = 0.14
    let markup = SpeechMarkup(
      segments: [], totalDuration: .milliseconds(1_500),
      frameProbabilities: probabilities)
    #expect(markup.hasSpeech == false)
    #expect(markup.salvageWholeBuffer == true)
    #expect(markup.metrics.maxFrameProbability == 0.14)
  }

  @Test("room tone is below the floor and stays discarded")
  func noSalvageOnRoomTone() {
    let markup = SpeechMarkup(
      segments: [], totalDuration: .milliseconds(1_500),
      frameProbabilities: [0.012, 0.054, 0.003])
    #expect(markup.salvageWholeBuffer == false)
  }

  @Test("the salvage floor is inclusive: a frame exactly on it still salvages")
  func salvageFloorIsInclusive() {
    let floor = SpeechThresholds.default.minSalvageFrameProbability
    let onTheFloor = SpeechMarkup(
      segments: [], totalDuration: .milliseconds(1_500),
      frameProbabilities: [0.01, floor])
    #expect(onTheFloor.salvageWholeBuffer == true)
    let justUnder = SpeechMarkup(
      segments: [], totalDuration: .milliseconds(1_500),
      frameProbabilities: [0.01, floor.nextDown])
    #expect(justUnder.salvageWholeBuffer == false)
  }

  @Test("a detector that reports no frames does not open the gate")
  func noSalvageWithoutFrames() {
    let markup = SpeechMarkup(segments: [], totalDuration: .milliseconds(1_500))
    #expect(markup.salvageWholeBuffer == false)
    #expect(markup.metrics.maxFrameProbability == nil)
  }

  @Test("a short utterance after a long pause is not discarded")
  func shortUtteranceAfterAPauseIsKept() {
    let markup = SpeechMarkup(
      segments: [segment(3_000, 3_300)],
      totalDuration: .milliseconds(3_400),
      frameProbabilities: [0.99])
    #expect(markup.hasSpeech)
  }

  @Test("a kept segment is transcribed from its own span, never the whole buffer")
  func aKeptSegmentNeverTriggersTheWholeBufferPath() {
    let markup = SpeechMarkup(
      segments: [segment(60_000, 60_400)],
      totalDuration: .seconds(120),
      frameProbabilities: [0.99])
    #expect(markup.hasSpeech)
    #expect(markup.salvageWholeBuffer == false)
  }

  @Test("metrics written before the new fields still decode")
  func metricsDecodeWithoutNewFields() throws {
    let legacy = """
      {"segmentCount":0,"speechFraction":0,"maxProbability":0,\
      "meanProbability":0,"totalMilliseconds":1522}
      """
    let decoded = try JSONDecoder().decode(
      SpeechMetrics.self,
      from: Data(legacy.utf8))
    #expect(decoded.totalMilliseconds == 1_522)
    #expect(decoded.maxFrameProbability == nil)
    #expect(decoded.peakLevel == nil)
    #expect(decoded.firstTokenProbability == nil)
  }

  @Test("the new fields survive a round trip")
  func newFieldsRoundTrip() throws {
    var metrics = SpeechMarkup(
      segments: [], totalDuration: .seconds(2),
      frameProbabilities: [0.2]
    ).metrics
    metrics.peakLevel = 0.031
    metrics.firstTokenProbability = 0.078
    let decoded = try JSONDecoder().decode(
      SpeechMetrics.self, from: try JSONEncoder().encode(metrics))
    #expect(decoded == metrics)
    #expect(decoded.peakLevel == 0.031)
    #expect(decoded.maxFrameProbability == 0.2)
    #expect(decoded.firstTokenProbability == 0.078)
  }

  @Test("extraction returns the segments, not the whole buffer")
  func extractionTakesSegmentsOnly() {
    let samples = (0..<16_000).map(Float.init)
    let extracted = SpeechMarkup.extract([segment(250, 500)], from: samples)
    #expect(extracted.count == 4_000)
    #expect(extracted.first == 4_000)
    #expect(extracted.last == 7_999)
  }

  @Test("the audio between two segments of one utterance is kept")
  func extractionKeepsTheSpanBetweenSegments() {
    let samples = (0..<16_000).map(Float.init)
    let extracted = SpeechMarkup.extract(
      [segment(100, 300), segment(700, 900)],
      from: samples)
    #expect(extracted.count == 12_800)
    #expect(extracted.first == 1_600)
    #expect(extracted.last == 14_399)
  }

  @Test("silence before the first segment and after the last is dropped")
  func extractionDropsTheOuterSilence() {
    let samples = (0..<16_000).map(Float.init)
    let extracted = SpeechMarkup.extract([segment(500, 600)], from: samples)
    #expect(extracted.count == 1_600)
    #expect(extracted.first == 8_000)
    #expect(extracted.last == 9_599)
  }

  @Test("an empty segment list extracts nothing")
  func emptyExtraction() {
    #expect(SpeechMarkup.extract([], from: [1, 2, 3]).isEmpty)
  }
}

@Suite("The start cue must not open the salvage gate")
struct SalvageCueTests {
  private func frames(
    cue: Float, rest: Float,
    cueMS: Int = 600, totalMS: Int = 10_000
  ) -> [Float] {
    let frameMS = 32
    let cueFrames = cueMS / frameMS
    let total = totalMS / frameMS
    return (0..<total).map { $0 < cueFrames ? cue : rest }
  }

  @Test("the cue alone does not salvage a silent buffer")
  func cueAloneDoesNotSalvage() {
    let markup = SpeechMarkup(
      segments: [], totalDuration: .milliseconds(10_000),
      frameProbabilities: frames(cue: 0.775, rest: 0.03),
      thresholds: .default)
    #expect(
      markup.salvageWholeBuffer == false,
      "our own start cue opened the gate on a buffer that is otherwise silence")
    #expect(markup.hasSpeech == false)
  }

  @Test("quiet speech after the cue still salvages")
  func speechAfterCueStillSalvages() {
    let markup = SpeechMarkup(
      segments: [], totalDuration: .milliseconds(10_000),
      frameProbabilities: frames(cue: 0.775, rest: 0.14),
      thresholds: .default)
    #expect(markup.salvageWholeBuffer == true)
  }

  @Test("the recorded maximum is still over every frame, cue included")
  func metricsStillSeeTheWholeBuffer() {
    let markup = SpeechMarkup(
      segments: [], totalDuration: .milliseconds(10_000),
      frameProbabilities: frames(cue: 0.775, rest: 0.03),
      thresholds: .default)
    #expect(markup.metrics.maxFrameProbability == 0.775)
  }

  @Test("a recording no longer than the cue does not salvage")
  func recordingShorterThanTheCue() {
    let markup = SpeechMarkup(
      segments: [], totalDuration: .milliseconds(400),
      frameProbabilities: frames(
        cue: 0.775, rest: 0.775,
        cueMS: 400, totalMS: 400),
      thresholds: .default)
    #expect(markup.salvageWholeBuffer == false)
  }
}
