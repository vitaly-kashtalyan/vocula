import Foundation
import VoculaKit
import whisper

public struct WhisperLanguage: Identifiable, Sendable, Hashable {
  public let code: String
  public let name: String
  public let displayName: String
  public let nativeName: String?

  public var id: String { code }

  public var titleWithNativeName: String {
    nativeName.map { "\(displayName) (\($0))" } ?? displayName
  }
}

public enum WhisperLanguages {
  public static let all: [WhisperLanguage] = {
    let english = Locale(identifier: "en_US")
    let interface = Locale.interface
    return (0...Int(whisper_lang_max_id())).compactMap { id -> WhisperLanguage? in
      guard let pointer = whisper_lang_str(Int32(id)) else { return nil }
      let code = String(cString: pointer)
      guard code != "auto" else { return nil }
      let name =
        english.localizedString(forLanguageCode: code)
        ?? whisper_lang_str_full(Int32(id))
        .map { String(cString: $0).capitalized(with: english) }
        ?? code.uppercased(with: .invariant)
      let shown =
        interface.localizedString(forLanguageCode: code)?
        .capitalized(with: interface) ?? name
      let locale = Locale(identifier: code)
      let native = locale.localizedString(forLanguageCode: code)?
        .capitalized(with: locale)
      return WhisperLanguage(
        code: code, name: name, displayName: shown,
        nativeName: native == shown ? nil : native)
    }
    .sorted {
      $0.displayName.compare(
        $1.displayName, options: [.caseInsensitive],
        range: nil, locale: interface) == .orderedAscending
    }
  }()

  private static let byCode = Dictionary(all.map { ($0.code, $0) }) { first, _ in first }

  public static func name(for code: String) -> String {
    byCode[code]?.name ?? code.uppercased(with: .invariant)
  }

  public static func language(for code: String) -> WhisperLanguage? { byCode[code] }
}
