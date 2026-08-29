import AppKit
import VoculaKit

@MainActor
enum Cue {
  private static let startCue = NSSound(named: "Frog")
  private static let stopCue = NSSound(named: "Submarine")

  private static func play(_ sound: NSSound?, volume: Float) {
    guard let sound else { return }
    // play() on a sounding NSSound is a silent no-op.
    sound.stop()
    sound.volume = volume
    sound.play()
  }

  static func playStart() {
    play(startCue, volume: 0.10)
  }

  static func play(for signal: DictationSignal) {
    switch signal {
    case .start:
      break
    case .stop:
      startCue?.stop()
      play(stopCue, volume: 0.05)
    case .cancel:
      startCue?.stop()
    }
  }
}
