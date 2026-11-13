import Foundation

public enum EngineFallback {
  public static func running(
    selected: ModelID, languages: [String], isReady: (ModelID) -> Bool
  ) -> ModelID? {
    if isReady(selected) { return selected }
    return ModelManifest.transcriptionModels.first { candidate in
      let family = ModelManifest.descriptor(for: candidate).family
      return candidate != selected && isReady(candidate)
        && languages.allSatisfy { EngineLanguages.supports($0, family) }
    }
  }

  public static func handOver(removed: ModelID, selected: ModelID) -> ModelID? {
    removed == selected && selected != .largeV3Turbo ? .largeV3Turbo : nil
  }
}
