import Foundation

extension Locale {
  public static let invariant = Locale(identifier: "en_US_POSIX")

  public static let interface = Locale(
    identifier: Bundle.main.preferredLocalizations.first ?? "en")
}
