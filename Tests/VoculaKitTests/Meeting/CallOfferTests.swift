import Testing
import VoculaKit

@Suite struct CallOfferTests {
  private let call = [AudioClient(pid: 7, input: true, output: true)]

  @Test func aCallIsOfferedOnceAfterTenSeconds() {
    var offer = CallOffer()
    #expect(offer.observe(call, at: 0, recording: false) == nil)
    #expect(offer.observe(call, at: 8, recording: false) == nil)
    #expect(offer.observe(call, at: 10, recording: false) == 7)
    #expect(offer.observe(call, at: 12, recording: false) == nil)
    #expect(offer.observe(call, at: 600, recording: false) == nil)
  }

  @Test func onlyAnAppThatBothListensAndPlaysIsACall() {
    var offer = CallOffer()
    let apart = [
      AudioClient(pid: 1, input: true, output: false),
      AudioClient(pid: 2, input: false, output: true),
    ]
    #expect(offer.observe(apart, at: 0, recording: false) == nil)
    #expect(offer.observe(apart, at: 60, recording: false) == nil)
  }

  @Test func aCallSeenWhileAMeetingRecordsIsNeverOffered() {
    var offer = CallOffer()
    _ = offer.observe(call, at: 0, recording: true)
    #expect(offer.observe(call, at: 20, recording: true) == nil)
    #expect(offer.observe(call, at: 40, recording: false) == nil)
  }

  @Test func aShortDropIsTheSameCallAndAnEndedOneIsOfferedAgain() {
    var offer = CallOffer()
    _ = offer.observe(call, at: 0, recording: false)
    #expect(offer.observe(call, at: 10, recording: false) == 7)
    #expect(offer.observe([], at: 20, recording: false) == nil)
    #expect(offer.observe(call, at: 25, recording: false) == nil)
    #expect(offer.observe([], at: 60, recording: false) == nil)
    #expect(offer.observe(call, at: 61, recording: false) == nil)
    #expect(offer.observe(call, at: 71, recording: false) == 7)
  }

  @Test func theEarliestOfTwoCallsIsOfferedFirst() {
    var offer = CallOffer()
    _ = offer.observe([AudioClient(pid: 9, input: true, output: true)], at: 0, recording: false)
    let both = [
      AudioClient(pid: 3, input: true, output: true),
      AudioClient(pid: 9, input: true, output: true),
    ]
    _ = offer.observe(both, at: 5, recording: false)
    #expect(offer.observe(both, at: 15, recording: false) == 9)
    #expect(offer.observe(both, at: 17, recording: false) == 3)
  }

  @Test func theAppIsTheOutermostBundle() {
    #expect(
      CallOffer.appPath(
        ofExecutable:
          "/Applications/zoom.us.app/Contents/Frameworks/CptHost.app/Contents/MacOS/CptHost")
        == "/Applications/zoom.us.app")
    #expect(CallOffer.appPath(ofExecutable: "/usr/libexec/avconferenced") == nil)
  }
}
