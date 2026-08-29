import Foundation

public enum NoSpeechNotice {
  public static let worthTellingAfter = Duration.seconds(4)

  public static func worthTelling(heldFor: Duration) -> Bool {
    heldFor >= worthTellingAfter
  }
}
