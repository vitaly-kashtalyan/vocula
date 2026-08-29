import Foundation
import Testing

@testable import VoculaKit

@Suite("Failing over to the next microphone mid-dictation")
struct DeviceFailoverTests {
  private let list = MicrophonePriorityList(devices: [
    RankedInputDevice(uid: "headset", name: "Headset"),
    RankedInputDevice(uid: "dongle", name: "Dongle"),
    RankedInputDevice(uid: "builtin", name: "Built-in"),
  ])

  private func next(
    after lost: String, connected: Set<String>,
    alreadyFailedOver: Int = 0
  ) -> String? {
    DeviceFailover.next(
      after: lost, priority: list, connected: connected,
      alreadyFailedOver: alreadyFailedOver)?.uid
  }

  @Test("the next-ranked connected device takes over")
  func theNextRankedDeviceTakesOver() {
    #expect(next(after: "headset", connected: ["dongle", "builtin"]) == "dongle")
  }

  @Test("the device that just died is never chosen again")
  func theLostDeviceIsExcluded() {
    #expect(next(after: "headset", connected: ["headset", "builtin"]) == "builtin")
  }

  @Test("the built-in microphone is the floor")
  func theBuiltInIsTheFloor() {
    #expect(next(after: "dongle", connected: ["builtin"]) == "builtin")
  }

  @Test("nothing left connected means no failover")
  func nothingLeftMeansNoFailover() {
    #expect(next(after: "headset", connected: ["headset"]) == nil)
    #expect(next(after: "headset", connected: []) == nil)
  }

  @Test("a flapping device cannot loop for ever")
  func failoverIsBounded() {
    let everything: Set<String> = ["dongle", "builtin"]
    #expect(next(after: "headset", connected: everything, alreadyFailedOver: 1) != nil)
    #expect(
      next(
        after: "headset", connected: everything,
        alreadyFailedOver: DeviceFailover.maximumPerSession) == nil)
  }

  @Test("a device outside the priority list is not reachable")
  func anUnrankedDeviceIsNotChosen() {
    #expect(next(after: "headset", connected: ["stranger"]) == nil)
  }
}
