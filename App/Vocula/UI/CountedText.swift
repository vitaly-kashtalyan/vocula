import Foundation
import VoculaKit

enum CountedText {
  static func text(
    _ copy: CountedCopy,
    bundle: Bundle = .main,
    locale: Locale = .interface
  ) -> String {
    let format = bundle.localizedString(forKey: copy.key, value: nil, table: nil)
    guard format != copy.key else { return "\(copy.count)" }
    let arguments: [CVarArg] = [copy.count] + copy.extra.map { $0 as CVarArg }
    return String(format: format, locale: locale, arguments: arguments)
  }
}
