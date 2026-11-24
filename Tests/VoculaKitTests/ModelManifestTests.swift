import Foundation
import Testing

@testable import VoculaKit

@Suite("Model manifest")
struct ModelManifestTests {
  @Test("every model is fetched over TLS")
  func everyModelIsFetchedOverTLS() {
    #expect(!ModelManifest.current.isEmpty)
    for model in ModelManifest.current {
      #expect(
        model.remoteURL.scheme == "https",
        "\(model.id) would be downloaded over \(model.remoteURL.scheme ?? "no scheme")")
    }
  }

  @Test("the weights are served from our own release, and moving them is deliberate")
  func theWeightsComeFromOurOwnRelease() {
    for model in ModelManifest.current {
      #expect(model.remoteURL.host() == "github.com")
      #expect(model.remoteURL.path().contains("/releases/download/models-v1/"))
      #expect(model.remoteURL.lastPathComponent == model.fileName)
    }
  }

  @Test("no two models share a file name")
  func fileNamesAreDistinct() {
    let names = ModelManifest.current.map(\.fileName)
    #expect(Set(names).count == names.count)
  }

  @Test("the speaker separation model is pinned, and it is not a transcription engine")
  func theDiarizerIsPinnedAndNotAnEngine() {
    let model = ModelManifest.descriptor(for: .speakerDiarizer)
    #expect(model.family == .parakeet)
    #expect(model.fileName == "speaker-diarizer-df2625a.zip")
    #expect(model.unpacked == "speaker-diarizer-df2625a")
    #expect(!ModelManifest.transcriptionModels.contains(.speakerDiarizer))
  }

  @Test("the Parakeet credit says FluidAudio also separates speakers, and whose weights")
  func theParakeetCreditNamesSpeakerSeparation() {
    let credit = ModelFamily.parakeet.engineCredit
    #expect(credit.contains("separates speakers"))
    for name in ["pyannote", "WeSpeaker", "BUT Speech@FIT", "CC-BY-4.0"] {
      #expect(credit.contains(name), "\(name)")
    }
  }
}
