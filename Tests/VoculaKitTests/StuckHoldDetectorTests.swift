import Testing

@testable import VoculaKit

@Suite("Stuck hold")
struct StuckHoldDetectorTests {
  @Test("while the modifier really is down, nothing is wrong")
  func modifierStillDown() {
    var detector = StuckHoldDetector()
    #expect(detector.poll(modifierIsDown: true) == .fine)
  }

  @Test("the modifier is up but no release arrived — the release was lost")
  func releaseWasLost() {
    var detector = StuckHoldDetector()
    #expect(detector.poll(modifierIsDown: false) == .releaseWasLost)
  }

  @Test("a released key is not a hold, so it is never polled")
  func aFinishedRecordingIsNotAHold() {
    var machine = GestureStateMachine(config: GestureConfig(primary: .fn))
    _ = machine.handle(.bindingDown(.milliseconds(0)))
    #expect(machine.isHoldingBinding == true)
    _ = machine.handle(.bindingUp(.milliseconds(400)))
    #expect(machine.isHoldingBinding == false)
  }

  @Test("reset re-arms the detector for the next recording")
  func resetReArms() {
    var detector = StuckHoldDetector()
    #expect(detector.poll(modifierIsDown: false) == .releaseWasLost)
    detector.reset()
    #expect(detector.poll(modifierIsDown: false) == .releaseWasLost)
  }

  @Test("a verdict is given once, not on every poll")
  func verdictIsGivenOnce() {
    var detector = StuckHoldDetector()
    #expect(detector.poll(modifierIsDown: false) == .releaseWasLost)
    #expect(detector.poll(modifierIsDown: false) == .fine)
  }
}
