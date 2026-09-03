import AppKit
import VoculaKit

enum Relaunch {
  static let sectionArgument = "VoculaReopenSection"

  // synchronize: applicationWillTerminate ends in _exit(0), which runs no atexit
  // handler, and CFPreferences' flush is one.
  static func request(_ section: SettingsSection, in defaults: UserDefaults = .standard) {
    defaults.set(section.rawValue, forKey: sectionArgument)
    defaults.synchronize()
  }

  static let lastVersionKey = "app.lastLaunchedVersion"

  static func sectionAfterAVersionChange(
    current: String, in defaults: UserDefaults = .standard
  ) -> SettingsSection? {
    defer { defaults.set(current, forKey: lastVersionKey) }
    guard let last = defaults.string(forKey: lastVersionKey), last != current else { return nil }
    return .permissions
  }

  static func takeRequestedSection(_ defaults: UserDefaults) -> SettingsSection? {
    let raw = defaults.string(forKey: sectionArgument)
    defaults.removeObject(forKey: sectionArgument)
    return raw.flatMap(SettingsSection.init(rawValue:))
  }

  static func now(reopening section: SettingsSection?) {
    let path = Bundle.main.bundleURL.path
    let reopen = section.map { ["--args", "-\(sectionArgument)", $0.rawValue] } ?? []
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments =
      [
        "-c",
        """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done
        open "$@"
        """, "sh", path,
      ] + reopen
    try? task.run()
    NSApp.terminate(nil)
  }
}

enum LaunchInterfaceLanguage {
  static let code = InterfaceLanguages.selected(
    stored: UserDefaults.standard.stringArray(forKey: InterfaceLanguages.defaultsKey),
    available: InterfaceLanguages.available(in: Bundle.main.localizations).map(\.code))
}
