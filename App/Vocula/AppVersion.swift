import Foundation

extension Bundle {
  var shortVersion: String {
    infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
  }

  var build: String? { infoDictionary?["CFBundleVersion"] as? String }

  var buildNumber: String { build ?? "—" }

  var versionLine: String { "Vocula \(shortVersion)" }

  var versionAndBuild: String {
    String(
      localized: "app.versionAndBuild",
      defaultValue: "Version \(shortVersion) (\(buildNumber))",
      comment: "App footer; the arguments are the marketing version and the build number.")
  }
}
