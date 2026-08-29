import Testing

@testable import VoculaKit

@Suite("Input liveness watchdog")
struct InputLivenessWatchdogTests {
  @Test("a microphone that never opens is not called dead")
  func startupIsNotDeath() {
    var watchdog = InputLivenessWatchdog()
    for _ in 0..<10 {
      #expect(watchdog.check(buffersDelivered: 0) == .alive)
    }
  }

  @Test("buffers still arriving read as alive")
  func flowingInputIsAlive() {
    var watchdog = InputLivenessWatchdog()
    #expect(watchdog.check(buffersDelivered: 4) == .alive)
    #expect(watchdog.check(buffersDelivered: 9) == .alive)
    #expect(watchdog.check(buffersDelivered: 14) == .alive)
  }

  @Test("a single quiet check is tolerated, the second is not")
  func silenceIsCalledOnTheSecondCheck() {
    var watchdog = InputLivenessWatchdog()
    #expect(watchdog.check(buffersDelivered: 5) == .alive)
    #expect(watchdog.check(buffersDelivered: 5) == .alive)
    #expect(watchdog.check(buffersDelivered: 5) == .dead)
  }

  @Test("audio returning after a repair rearms the watchdog for the next failure")
  func rearmsAfterRepair() {
    var watchdog = InputLivenessWatchdog()
    _ = watchdog.check(buffersDelivered: 5)
    _ = watchdog.check(buffersDelivered: 5)
    #expect(watchdog.check(buffersDelivered: 5) == .dead)

    #expect(watchdog.check(buffersDelivered: 12) == .alive)
    #expect(watchdog.check(buffersDelivered: 12) == .alive)
    #expect(watchdog.check(buffersDelivered: 12) == .dead)
  }

  @Test("one late buffer inside the window clears the count rather than adding to it")
  func aLateBufferResetsTheWindow() {
    var watchdog = InputLivenessWatchdog()
    _ = watchdog.check(buffersDelivered: 5)
    #expect(watchdog.check(buffersDelivered: 5) == .alive)
    #expect(watchdog.check(buffersDelivered: 6) == .alive)
    #expect(watchdog.check(buffersDelivered: 6) == .alive)
    #expect(watchdog.check(buffersDelivered: 6) == .dead)
  }

  @Test("a stricter tolerance reports sooner")
  func toleranceIsHonoured() {
    var watchdog = InputLivenessWatchdog(tolerance: 1)
    #expect(watchdog.check(buffersDelivered: 3) == .alive)
    #expect(watchdog.check(buffersDelivered: 3) == .dead)
  }
}
