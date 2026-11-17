import Testing

@testable import VoculaKit

@Suite struct MeetingOnboardingCopyTests {
  @Test func theMicrophoneLinesNameMeetings() {
    #expect(
      OnboardingModel.text(forKey: "onboarding.microphone.explanation.granted")
        == "Switched on only while you dictate or record a meeting. The rest of the time the app hears nothing at all."
    )
    #expect(
      OnboardingModel.text(forKey: "onboarding.microphone.explanation.willAsk")
        == "Switched on only while you dictate or record a meeting. macOS shows this dialog once per install: if you dismiss it, the app cannot ask again."
    )
  }
}
