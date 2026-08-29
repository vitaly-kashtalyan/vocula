import AppKit

enum Announce {
  @MainActor
  static func say(_ text: String, priority: NSAccessibilityPriorityLevel = .high) {
    guard !text.isEmpty else { return }
    NSAccessibility.post(
      element: NSApp as Any,
      notification: .announcementRequested,
      userInfo: [
        .announcement: text,
        .priority: priority.rawValue,
      ])
  }
}
