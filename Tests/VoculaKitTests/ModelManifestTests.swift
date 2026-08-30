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
}
