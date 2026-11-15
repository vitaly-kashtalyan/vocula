import Foundation

public enum InstallPlacement: Equatable, Sendable {
  case translocated
  case readOnlyVolume

  public static func problem(bundlePath: String, volumeIsReadOnly: Bool) -> InstallPlacement? {
    guard volumeIsReadOnly else { return nil }
    return bundlePath.contains("/AppTranslocation/") ? .translocated : .readOnlyVolume
  }
}
