import AVFoundation
import AppKit
import ApplicationServices
import IOKit.hid
import VoculaKit

struct PermissionSnapshot {
  var microphone: OnboardingStatus
  var inputMonitoring: OnboardingStatus
  var accessibility: OnboardingStatus
  var autostart: OnboardingStatus
}

@MainActor
enum PermissionState {
  static func current() -> PermissionSnapshot {
    PermissionSnapshot(
      microphone: microphone(),
      inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        ? .granted : .missing,
      accessibility: AXIsProcessTrusted() ? .granted : .missing,
      autostart: LoginItem.status())
  }

  static func microphone() -> OnboardingStatus {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return .granted
    case .notDetermined: return .unknown
    case .restricted: return .restricted
    default: return .missing
    }
  }

  static func requestMicrophone() async -> Bool {
    await AVCaptureDevice.requestAccess(for: .audio)
  }

  static func requestAccessibility() async -> Bool {
    if AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
      return true
    }
    guard hasAsked(.accessibility) else {
      markAsked(.accessibility)
      return true
    }
    return await open(.accessibility)
  }

  private static func hasAsked(_ pane: Pane) -> Bool {
    UserDefaults.standard.bool(forKey: "permission.asked.\(pane)")
  }

  private static func markAsked(_ pane: Pane) {
    UserDefaults.standard.set(true, forKey: "permission.asked.\(pane)")
  }

  enum Pane: CaseIterable {
    case inputMonitoring, accessibility, microphone, loginItems, keyboard, screenTime

    var candidates: [String] {
      switch self {
      case .inputMonitoring:
        return [
          "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
          "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
          "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
      case .accessibility:
        return [
          "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
          "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
          "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
      case .microphone:
        return [
          "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone",
          "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
          "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
      case .loginItems:
        return ["x-apple.systempreferences:com.apple.LoginItems-Settings.extension"]
      case .keyboard:
        return ["x-apple.systempreferences:com.apple.Keyboard-Settings.extension"]
      case .screenTime:
        return ["x-apple.systempreferences:com.apple.Screen-Time-Settings.extension"]
      }
    }
  }

  static func open(_ pane: Pane) async -> Bool {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    for candidate in pane.candidates {
      guard let url = URL(string: candidate) else { continue }
      if (try? await NSWorkspace.shared.open(url, configuration: configuration)) != nil {
        return true
      }
    }
    return false
  }
}
