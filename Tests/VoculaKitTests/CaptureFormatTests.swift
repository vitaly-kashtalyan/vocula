import Testing

@testable import VoculaKit

@Suite("Capture format")
struct CaptureFormatTests {
  @Test("a normal microphone is taken at its own rate and channel count")
  func ordinaryDevice() {
    let format = CaptureFormat.client(hardwareRate: 48_000, hardwareChannels: 1)
    #expect(format == CaptureFormat(rate: 48_000, channels: 1))
  }

  @Test("a multichannel interface keeps its channel count")
  func multichannelIsCarriedThrough() {
    #expect(
      CaptureFormat.client(hardwareRate: 96_000, hardwareChannels: 16)
        == CaptureFormat(rate: 96_000, channels: 16))
  }

  @Test("a device reporting no rate cannot be recorded from")
  func zeroRateIsRefused() {
    #expect(CaptureFormat.client(hardwareRate: 0, hardwareChannels: 1) == nil)
  }

  @Test("a device reporting no channels cannot be recorded from")
  func zeroChannelsIsRefused() {
    #expect(CaptureFormat.client(hardwareRate: 48_000, hardwareChannels: 0) == nil)
  }

  @Test("a negative rate is refused rather than trusted")
  func negativeRateIsRefused() {
    #expect(CaptureFormat.client(hardwareRate: -48_000, hardwareChannels: 1) == nil)
  }
}
