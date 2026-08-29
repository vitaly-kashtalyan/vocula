import Testing

@testable import VoculaKit

@Suite("Input meter policy")
struct InputMeterPolicyTests {
  private func request(
    onDemand: Bool = false,
    active: Bool = true,
    asked: Bool = false
  ) -> InputMeterRequest {
    InputMeterRequest(
      opensOnDemandOnly: onDemand,
      appIsActive: active,
      userAskedToListen: asked)
  }

  @Test("a wired microphone is listened to as soon as the app is in front")
  func wiredOpensOnItsOwn() {
    #expect(InputMeterPolicy.shouldListen(request()))
  }

  @Test("a radio-link microphone is never opened unasked, and is opened when asked")
  func onDemandNeedsAsking() {
    #expect(!InputMeterPolicy.shouldListen(request(onDemand: true)))
    #expect(InputMeterPolicy.shouldListen(request(onDemand: true, asked: true)))
  }

  @Test("leaving the app closes the microphone, asked for or not")
  func leavingClosesIt() {
    #expect(!InputMeterPolicy.shouldListen(request(active: false)))
    #expect(!InputMeterPolicy.shouldListen(request(onDemand: true, active: false, asked: true)))
  }
}
