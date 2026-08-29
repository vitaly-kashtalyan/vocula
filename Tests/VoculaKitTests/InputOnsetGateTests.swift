import Testing

@testable import VoculaKit

@Suite("Input onset gate")
struct InputOnsetGateTests {
  @Test("digital silence is not the microphone waking up")
  func silenceKeepsItShut() {
    var gate = InputOnsetGate()
    #expect(gate.level(0) == .stillWaiting)
    #expect(gate.level(0) == .stillWaiting)
    #expect(!gate.isOpen)
  }

  @Test("the first sample above silence opens it, and only the first")
  func firstSignalOpensItOnce() {
    var gate = InputOnsetGate()
    #expect(gate.level(0) == .stillWaiting)
    #expect(gate.level(0.0001) == .signal)
    #expect(gate.isOpen)
    #expect(gate.level(0.5) == .stillWaiting)
  }

  @Test("the bound opens it when nothing ever rises above silence")
  func boundOpensIt() {
    var gate = InputOnsetGate()
    #expect(gate.level(0) == .stillWaiting)
    #expect(gate.boundReached() == .bound)
    #expect(gate.isOpen)
  }

  @Test("a bound reached after the microphone woke up changes nothing")
  func boundAfterSignalIsInert() {
    var gate = InputOnsetGate()
    #expect(gate.level(0.2) == .signal)
    #expect(gate.boundReached() == .stillWaiting)
  }
}
