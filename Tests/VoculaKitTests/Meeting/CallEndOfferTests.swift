import Testing
import VoculaKit

@Suite struct CallEndOfferTests {
  private let call = [AudioClient(pid: 7, input: true, output: true)]
  private let muted = [AudioClient(pid: 7, input: false, output: true)]

  private func feed(
    _ offer: inout CallEndOffer, _ clients: [AudioClient], from start: Double, to end: Double,
    recording: Bool = true
  ) -> [CallEndOffer.Change] {
    stride(from: start, through: end, by: 2).compactMap {
      offer.observe(clients, at: $0, recording: recording)
    }
  }

  @Test func aCallThatLeavesTheMicrophoneIsOfferedOnceAfterThirtySeconds() {
    var offer = CallEndOffer()
    #expect(feed(&offer, call, from: 0, to: 20).isEmpty)
    #expect(feed(&offer, [], from: 22, to: 48).isEmpty)
    #expect(offer.observe([], at: 50, recording: true) == .offer(7))
    #expect(feed(&offer, [], from: 52, to: 600).isEmpty)
  }

  @Test func aMuteShorterThanThirtySecondsIsTheSameCall() {
    var offer = CallEndOffer()
    _ = feed(&offer, call, from: 0, to: 20)
    #expect(feed(&offer, muted, from: 22, to: 48).isEmpty)
    #expect(feed(&offer, call, from: 50, to: 60).isEmpty)
    #expect(feed(&offer, muted, from: 62, to: 88).isEmpty)
    #expect(offer.observe(muted, at: 90, recording: true) == .offer(7))
  }

  @Test func anAppThatQuitsHasLeftTheMicrophone() {
    var offer = CallEndOffer()
    _ = feed(&offer, call, from: 0, to: 10)
    #expect(
      feed(&offer, [AudioClient(pid: 3, input: false, output: true)], from: 12, to: 38).isEmpty)
    #expect(offer.observe([], at: 40, recording: true) == .offer(7))
  }

  @Test func withTwoCallsTheOfferWaitsForTheLastAndNamesIt() {
    var offer = CallEndOffer()
    let both = [
      AudioClient(pid: 3, input: true, output: true),
      AudioClient(pid: 9, input: true, output: true),
    ]
    _ = feed(&offer, both, from: 0, to: 20)
    #expect(
      feed(&offer, [AudioClient(pid: 9, input: true, output: true)], from: 22, to: 40).isEmpty)
    #expect(feed(&offer, [], from: 42, to: 68).isEmpty)
    #expect(offer.observe([], at: 70, recording: true) == .offer(9))
  }

  @Test func aRecordingThatNeverSawACallIsNeverOffered() {
    var offer = CallEndOffer()
    let apart = [
      AudioClient(pid: 1, input: true, output: false),
      AudioClient(pid: 2, input: false, output: true),
    ]
    #expect(feed(&offer, apart, from: 0, to: 60).isEmpty)
    #expect(feed(&offer, call, from: 62, to: 70).isEmpty)
    #expect(feed(&offer, [], from: 72, to: 600).isEmpty)
  }

  @Test func aCallBeforeTheRecordingCountsOnlyOnceSeenDuringIt() {
    var offer = CallEndOffer()
    #expect(feed(&offer, call, from: 0, to: 60, recording: false).isEmpty)
    #expect(feed(&offer, [], from: 62, to: 600).isEmpty)
  }

  @Test func theMeetingStoppingWithdrawsTheOfferAndForgetsTheCall() {
    var offer = CallEndOffer()
    _ = feed(&offer, call, from: 0, to: 10)
    #expect(feed(&offer, [], from: 12, to: 40) == [.offer(7)])
    #expect(offer.observe([], at: 42, recording: false) == .withdraw)
    #expect(offer.observe([], at: 44, recording: false) == nil)
    #expect(feed(&offer, [], from: 46, to: 600).isEmpty)
  }

  @Test func theCallTakingTheMicrophoneAgainWithdrawsTheOfferUntilItLeavesAgain() {
    var offer = CallEndOffer()
    _ = feed(&offer, call, from: 0, to: 10)
    #expect(feed(&offer, [], from: 12, to: 40) == [.offer(7)])
    #expect(offer.observe(call, at: 42, recording: true) == .withdraw)
    #expect(feed(&offer, call, from: 44, to: 50).isEmpty)
    #expect(feed(&offer, [], from: 52, to: 78).isEmpty)
    #expect(offer.observe([], at: 80, recording: true) == .offer(7))
  }

  @Test func anAnsweredOfferIsNotRepeatedDuringThatRecording() {
    var offer = CallEndOffer()
    _ = feed(&offer, call, from: 0, to: 10)
    #expect(feed(&offer, [], from: 12, to: 40) == [.offer(7)])
    offer.answered()
    #expect(feed(&offer, call, from: 42, to: 60).isEmpty)
    #expect(feed(&offer, [], from: 62, to: 600).isEmpty)
    #expect(offer.observe([], at: 602, recording: false) == nil)
    _ = feed(&offer, call, from: 604, to: 614)
    #expect(feed(&offer, [], from: 616, to: 644) == [.offer(7)])
  }
}

@Suite struct QuietOfferTests {
  private let call = [AudioClient(pid: 7, input: true, output: true)]

  private func feed(
    _ offer: inout CallEndOffer, _ clients: [AudioClient] = [], from start: Double,
    to end: Double, quiet: Bool
  ) -> [CallEndOffer.Change] {
    stride(from: start, through: end, by: 2).compactMap {
      offer.observe(clients, at: $0, recording: true, quiet: quiet)
    }
  }

  @Test func aQuietMeetingWithoutACallIsOfferedOnce() {
    var offer = CallEndOffer()
    #expect(feed(&offer, from: 0, to: 118, quiet: false).isEmpty)
    #expect(offer.observe([], at: 120, recording: true, quiet: true) == .offerQuiet)
    #expect(feed(&offer, from: 122, to: 600, quiet: true).isEmpty)
  }

  @Test func soundWithdrawsTheQuietOffer() {
    var offer = CallEndOffer()
    #expect(feed(&offer, from: 0, to: 4, quiet: true) == [.offerQuiet])
    #expect(offer.observe([], at: 6, recording: true, quiet: false) == .withdraw)
    #expect(feed(&offer, from: 8, to: 20, quiet: false).isEmpty)
    #expect(offer.observe([], at: 22, recording: true, quiet: true) == .offerQuiet)
  }

  @Test func theRecordingStoppingWithdrawsTheQuietOffer() {
    var offer = CallEndOffer()
    #expect(feed(&offer, from: 0, to: 4, quiet: true) == [.offerQuiet])
    #expect(offer.observe([], at: 6, recording: false, quiet: true) == .withdraw)
    #expect(offer.observe([], at: 8, recording: false, quiet: false) == nil)
  }

  @Test func keepRecordingWaitsForSoundAndTwoMoreQuietMinutes() {
    var offer = CallEndOffer()
    #expect(feed(&offer, from: 0, to: 4, quiet: true) == [.offerQuiet])
    offer.answered()
    #expect(feed(&offer, from: 6, to: 600, quiet: true).isEmpty)
    #expect(feed(&offer, from: 602, to: 604, quiet: false).isEmpty)
    #expect(offer.observe([], at: 606, recording: true, quiet: true) == .offerQuiet)
  }

  @Test func keepingTheQuietOfferLeavesTheCallEndOffer() {
    var offer = CallEndOffer()
    _ = feed(&offer, call, from: 0, to: 10, quiet: false)
    #expect(feed(&offer, call, from: 12, to: 14, quiet: true) == [.offerQuiet])
    offer.answered()
    #expect(feed(&offer, from: 16, to: 42, quiet: true).isEmpty)
    #expect(offer.observe([], at: 44, recording: true, quiet: true) == .offer(7))
  }

  @Test func theCallEndOfferWinsWhenBothAreDue() {
    var offer = CallEndOffer()
    _ = feed(&offer, call, from: 0, to: 10, quiet: false)
    #expect(feed(&offer, from: 12, to: 38, quiet: false).isEmpty)
    #expect(offer.observe([], at: 40, recording: true, quiet: true) == .offer(7))
    #expect(feed(&offer, from: 42, to: 600, quiet: true).isEmpty)
  }

  @Test func theCallEndOfferTakesThePlaceOfAShownQuietOffer() {
    var offer = CallEndOffer()
    _ = feed(&offer, call, from: 0, to: 10, quiet: false)
    #expect(feed(&offer, from: 12, to: 14, quiet: true) == [.offerQuiet])
    #expect(feed(&offer, from: 16, to: 40, quiet: true) == [.offer(7)])
    #expect(offer.observe([], at: 42, recording: false, quiet: true) == .withdraw)
  }

  @Test func answeringTheCallEndOfferKeepsRecordingThroughTheQuiet() {
    var offer = CallEndOffer()
    _ = feed(&offer, call, from: 0, to: 10, quiet: false)
    #expect(feed(&offer, from: 12, to: 38, quiet: false).isEmpty)
    #expect(offer.observe([], at: 40, recording: true, quiet: true) == .offer(7))
    offer.answered()
    #expect(feed(&offer, from: 42, to: 600, quiet: true).isEmpty)
    _ = feed(&offer, from: 602, to: 604, quiet: false)
    #expect(offer.observe([], at: 606, recording: true, quiet: true) == .offerQuiet)
  }

  @Test func theCallTakingTheMicrophoneBackHandsThePanelToTheQuietOffer() {
    var offer = CallEndOffer()
    _ = feed(&offer, call, from: 0, to: 10, quiet: false)
    #expect(feed(&offer, from: 12, to: 38, quiet: false).isEmpty)
    #expect(offer.observe([], at: 40, recording: true, quiet: true) == .offer(7))
    #expect(offer.observe(call, at: 42, recording: true, quiet: true) == .offerQuiet)
  }
}
