import Foundation

public enum EngineDefault {
  public static func choose(languages: [String]) -> ModelID {
    languages.allSatisfy(EngineLanguages.parakeetCodes.contains) ? .parakeetUltra : .largeV3Turbo
  }

  public static func baseCodes(_ identifiers: [String]) -> [String] {
    identifiers.compactMap {
      Locale.Language(identifier: $0).languageCode?.identifier.lowercased(with: .invariant)
    }
  }
}
