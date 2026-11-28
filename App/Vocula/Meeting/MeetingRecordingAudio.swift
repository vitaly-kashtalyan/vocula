import AVFoundation
import Foundation
import Observation
import VoculaKit

protocol MeetingPlayer: AnyObject {
  var duration: TimeInterval { get }
  var currentTime: TimeInterval { get set }
  var isPlaying: Bool { get }
  func play() -> Bool
  func pause()
  func stop()
}

extension AVAudioPlayer: MeetingPlayer {}

enum MeetingPlayable: Equatable, Sendable {
  case wav(Data)
  case failed(step: String, code: Int)
}

@MainActor @Observable
final class MeetingPlayback {
  enum Phase: Equatable {
    case loading
    case playing
    case paused
  }

  enum Outcome: Equatable {
    case started
    case superseded
    case failed(step: String, code: Int)
  }

  private(set) var meeting: UUID?
  private(set) var phase = Phase.loading
  private(set) var position: TimeInterval = 0
  private(set) var duration: TimeInterval = 0

  @ObservationIgnored private let load: @Sendable (UUID) async -> MeetingPlayable
  @ObservationIgnored private let makePlayer: @MainActor (Data) -> (any MeetingPlayer)?
  @ObservationIgnored private let tick: @Sendable (Duration) async throws -> Void
  @ObservationIgnored private var player: (any MeetingPlayer)?
  @ObservationIgnored private var loading: Task<MeetingPlayable, Never>?
  @ObservationIgnored private var ticker: Task<Void, Never>?

  init(
    load: @escaping @Sendable (UUID) async -> MeetingPlayable,
    makePlayer: @escaping @MainActor (Data) -> (any MeetingPlayer)?,
    tick: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.load = load
    self.makePlayer = makePlayer
    self.tick = tick
  }

  func play(_ id: UUID) async -> Outcome {
    stop()
    meeting = id
    let load = load
    let task = Task { await load(id) }
    loading = task
    let loaded = await task.value
    guard loading == task else { return .superseded }
    loading = nil
    switch loaded {
    case .failed(let step, let code):
      stop()
      return .failed(step: step, code: code)
    case .wav(let data):
      guard let player = makePlayer(data), player.play() else {
        stop()
        return .failed(step: "player", code: 0)
      }
      self.player = player
      duration = player.duration
      position = player.currentTime
      phase = .playing
      startTicking()
      return .started
    }
  }

  func pauseOrResume() {
    guard let player else { return }
    switch phase {
    case .playing:
      player.pause()
      ticker?.cancel()
      position = player.currentTime
      phase = .paused
    case .paused:
      guard player.play() else { return }
      phase = .playing
      startTicking()
    case .loading:
      break
    }
  }

  func seek(to time: TimeInterval) {
    guard let player else { return }
    player.currentTime = min(max(0, time), duration)
    position = player.currentTime
  }

  func stop() {
    loading?.cancel()
    loading = nil
    ticker?.cancel()
    ticker = nil
    player?.stop()
    player = nil
    if meeting != nil { meeting = nil }
    if phase != .loading { phase = .loading }
    if position != 0 { position = 0 }
    if duration != 0 { duration = 0 }
  }

  private func startTicking() {
    ticker?.cancel()
    let tick = tick
    ticker = Task { [weak self] in
      while true {
        do { try await tick(.milliseconds(250)) } catch { return }
        guard !Task.isCancelled, let self, let player = self.player else { return }
        guard player.isPlaying else {
          self.stop()
          return
        }
        if self.position != player.currentTime { self.position = player.currentTime }
      }
    }
  }
}

enum MeetingAudioFile {
  private static let framesPerWrite = 960_000

  static func writeLossless(mic: [Int16], system: [Int16], to url: URL) throws {
    let file = try AVAudioFile(
      forWriting: url,
      settings: [
        AVFormatIDKey: kAudioFormatAppleLossless,
        AVSampleRateKey: Double(MeetingRecording.sampleRate),
        AVNumberOfChannelsKey: 2,
        AVEncoderBitDepthHintKey: 16,
      ], commonFormat: .pcmFormatInt16, interleaved: false)
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(framesPerWrite)),
      let channels = buffer.int16ChannelData
    else { throw CocoaError(.fileWriteUnknown) }
    let frames = max(mic.count, system.count)
    var start = 0
    while start < frames {
      let count = min(framesPerWrite, frames - start)
      copy(mic, from: start, count: count, to: channels[0])
      copy(system, from: start, count: count, to: channels[1])
      buffer.frameLength = AVAudioFrameCount(count)
      try file.write(from: buffer)
      start += count
    }
    file.close()
  }

  private static func copy(
    _ track: [Int16], from start: Int, count: Int, to channel: UnsafeMutablePointer<Int16>
  ) {
    let available = max(0, min(count, track.count - start))
    track.withUnsafeBufferPointer { source in
      guard available > 0, let base = source.baseAddress else { return }
      channel.update(from: base + start, count: available)
    }
    (channel + available).update(repeating: 0, count: count - available)
  }
}
