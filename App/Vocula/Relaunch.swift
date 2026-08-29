import AppKit
import VoculaKit

enum Relaunch {
  static let sectionArgument = "VoculaReopenSection"

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
