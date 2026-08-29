import Foundation

public struct SpeechSegment: Equatable, Sendable, Codable {
  public let start: Duration
  public let end: Duration
  public let probability: Float

  public init(start: Duration, end: Duration, probability: Float) {
    self.start = start
    self.end = end
    self.probability = probability
  }

  public var duration: Duration { end - start }
}

public struct SpeechMetrics: Equatable, Sendable, Codable {
  public let segmentCount: Int
  public let speechFraction: Double
  public let maxProbability: Float
  public let meanProbability: Float
  public let totalMilliseconds: Int
  public var maxFrameProbability: Float? = nil
  public var peakLevel: Float? = nil
  public var firstTokenProbability: Float? = nil
}

public struct SpeechThresholds: Equatable, Sendable {
  public var minProbability: Float
  public var vadFrameThreshold: Float
  public var minSegmentDuration: Duration
  public var minSalvageFrameProbability: Float
  public var salvageIgnoresLeadingMilliseconds: Int

  public init(
    minProbability: Float = 0.4,
    vadFrameThreshold: Float = 0.5,
    minSegmentDuration: Duration = .milliseconds(200),
    minSalvageFrameProbability: Float = 0.1,
    salvageIgnoresLeadingMilliseconds: Int = 600
  ) {
    self.minProbability = minProbability
    self.vadFrameThreshold = vadFrameThreshold
    self.minSegmentDuration = minSegmentDuration
    self.minSalvageFrameProbability = minSalvageFrameProbability
    self.salvageIgnoresLeadingMilliseconds = salvageIgnoresLeadingMilliseconds
  }

  public static let `default` = SpeechThresholds()
}

public struct SpeechMarkup: Equatable, Sendable {
  public let segments: [SpeechSegment]
  public let metrics: SpeechMetrics
  public let hasSpeech: Bool
  public let salvageWholeBuffer: Bool

  public init(
    segments raw: [SpeechSegment], totalDuration: Duration,
    frameProbabilities: [Float] = [],
    thresholds: SpeechThresholds = .default
  ) {
    let kept = raw.filter {
      $0.probability >= thresholds.minProbability
        && $0.duration >= thresholds.minSegmentDuration
    }
    self.segments = kept

    let totalMS = max(totalDuration.milliseconds, 1)
    let speechMS = kept.reduce(0) { $0 + $1.duration.milliseconds }
    let fraction = Double(speechMS) / Double(totalMS)
    let maxFrame = frameProbabilities.max()
    self.metrics = SpeechMetrics(
      segmentCount: kept.count,
      speechFraction: fraction,
      maxProbability: raw.map(\.probability).max() ?? 0,
      meanProbability: raw.isEmpty
        ? 0
        : raw.reduce(Float(0)) { $0 + $1.probability } / Float(raw.count),
      totalMilliseconds: totalMS,
      maxFrameProbability: maxFrame)
    self.hasSpeech = !kept.isEmpty
    let leadFrames: Int
    if frameProbabilities.isEmpty || thresholds.salvageIgnoresLeadingMilliseconds <= 0 {
      leadFrames = 0
    } else {
      let frameMS = Double(totalMS) / Double(frameProbabilities.count)
      leadFrames = Int(
        (Double(thresholds.salvageIgnoresLeadingMilliseconds)
          / frameMS).rounded(.up))
    }
    let maxFrameAfterCue = frameProbabilities.dropFirst(leadFrames).max()
    self.salvageWholeBuffer =
      kept.isEmpty
      && (maxFrameAfterCue ?? 0) >= thresholds.minSalvageFrameProbability
  }

  public static func extract(_ segments: [SpeechSegment], from samples: [Float]) -> [Float] {
    guard !samples.isEmpty,
      let first = segments.map(\.start.milliseconds).min(),
      let last = segments.map(\.end.milliseconds).max()
    else { return [] }
    let rate = AudioFormat.sampleRate / 1000
    let from = max(0, Int(Double(first) * rate))
    let to = min(samples.count, Int(Double(last) * rate))
    guard from < to else { return [] }
    return Array(samples[from..<to])
  }
}
