import Foundation
import Testing

@testable import Vocula

struct SettingsSectionTests {
  @Test("every section belongs to exactly one sidebar group")
  func groupsCoverEverySectionOnce() {
    let grouped = SettingsSection.groups.flatMap(\.sections)
    #expect(Set(grouped) == Set(SettingsSection.allCases))
    #expect(grouped.count == SettingsSection.allCases.count, "a section is listed twice")
  }

  @Test("the sidebar reads Status first and App last")
  func order() {
    #expect(
      SettingsSection.groups.flatMap(\.sections) == [
        .status, .permissions, .keyboard, .languages, .microphone, .models,
        .history, .diagnostics, .licence, .appearance,
      ])
    #expect(SettingsSection.groups.map(\.id) == ["top", "dictation", "data", "app"])
    #expect(SettingsSection.groups.map { $0.title == nil } == [true, false, false, false])
  }

  @Test("every section has a title and an icon")
  func titlesAndIcons() {
    for section in SettingsSection.allCases {
      #expect(!String(localized: section.title).isEmpty)
      #expect(!section.systemImage.isEmpty)
    }
  }

  private func inEnglish(_ resource: LocalizedStringResource) -> String {
    var copy = resource
    copy.locale = Locale(identifier: "en")
    return String(localized: copy)
  }

  @Test("the sidebar says what it has always said")
  func englishTitles() {
    #expect(
      SettingsSection.allCases.map { inEnglish($0.title) }
        == [
          "Status", "Permissions", "Keyboard", "Languages", "Microphone", "Models",
          "History", "Diagnostics", "Licence", "Appearance",
        ])
    #expect(
      SettingsSection.groups.compactMap { $0.title }.map { inEnglish($0) }
        == ["Dictation", "Data", "App"])
  }
}

@Suite("A self-requested relaunch comes back to the same place")
struct RelaunchSectionTests {
  @Test("every section survives the round trip", arguments: SettingsSection.allCases)
  func rawValuesRoundTrip(_ section: SettingsSection) {
    #expect(SettingsSection(rawValue: section.rawValue) == section)
  }

  @Test("an argument naming nothing reopens nothing, rather than guessing")
  func anUnknownSectionIsRefused() {
    #expect(SettingsSection(rawValue: "appearances") == nil)
    #expect(SettingsSection(rawValue: "") == nil)
  }

  @Test("a stored request is answered once, and taken with it")
  func aStoredRequestIsConsumed() throws {
    let domain = "app.vocula.mac.relaunchtest"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defaults.removePersistentDomain(forName: domain)
    defer { defaults.removePersistentDomain(forName: domain) }

    #expect(Relaunch.takeRequestedSection(defaults) == nil)
    Relaunch.request(.permissions, in: defaults)
    #expect(Relaunch.takeRequestedSection(defaults) == .permissions)
    #expect(Relaunch.takeRequestedSection(defaults) == nil)
  }

  @Test("an upgrade from a build that never recorded still lands, once")
  func anUntrackedUpgradeLands() throws {
    let (defaults, domain) = try suite("upgrade")
    defer { defaults.removePersistentDomain(forName: domain) }

    #expect(
      Relaunch.sectionAfterAVersionChange(
        current: "11", upgradedFromAnUntrackedBuild: true, in: defaults) == .permissions)
    #expect(defaults.string(forKey: Relaunch.lastVersionKey) == "11")
    #expect(
      Relaunch.sectionAfterAVersionChange(
        current: "11", upgradedFromAnUntrackedBuild: true, in: defaults) == nil)
  }

  @Test("a first install records the build and opens nothing")
  func aFirstInstallIsSilent() throws {
    let (defaults, domain) = try suite("fresh")
    defer { defaults.removePersistentDomain(forName: domain) }

    #expect(
      Relaunch.sectionAfterAVersionChange(
        current: "11", upgradedFromAnUntrackedBuild: false, in: defaults) == nil)
    #expect(defaults.string(forKey: Relaunch.lastVersionKey) == "11")
  }

  @Test("a build the machine has not run before opens the window, once")
  func aChangedVersionLands() throws {
    let (defaults, domain) = try suite("version")
    defer { defaults.removePersistentDomain(forName: domain) }

    _ = Relaunch.sectionAfterAVersionChange(
      current: "10", upgradedFromAnUntrackedBuild: false, in: defaults)
    #expect(
      Relaunch.sectionAfterAVersionChange(
        current: "10", upgradedFromAnUntrackedBuild: false, in: defaults) == nil)
    #expect(
      Relaunch.sectionAfterAVersionChange(
        current: "11", upgradedFromAnUntrackedBuild: false, in: defaults) == .permissions)
    #expect(
      Relaunch.sectionAfterAVersionChange(
        current: "11", upgradedFromAnUntrackedBuild: false, in: defaults) == nil)
  }

  @Test("a downgrade is a version change too, and is not special-cased")
  func aDowngradeLands() throws {
    let (defaults, domain) = try suite("downgrade")
    defer { defaults.removePersistentDomain(forName: domain) }

    _ = Relaunch.sectionAfterAVersionChange(
      current: "11", upgradedFromAnUntrackedBuild: false, in: defaults)
    #expect(
      Relaunch.sectionAfterAVersionChange(
        current: "10", upgradedFromAnUntrackedBuild: false, in: defaults) == .permissions)
  }

  @Test("a build that will not say its version records nothing and lands nowhere")
  func anUnreadableVersionIsInert() throws {
    let (defaults, domain) = try suite("unreadable")
    defer { defaults.removePersistentDomain(forName: domain) }

    #expect(
      Relaunch.sectionAfterAVersionChange(
        current: nil, upgradedFromAnUntrackedBuild: true, in: defaults) == nil)
    #expect(defaults.string(forKey: Relaunch.lastVersionKey) == nil)
  }

  private func suite(_ name: String) throws -> (UserDefaults, String) {
    let domain = "app.vocula.mac.\(name)test"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defaults.removePersistentDomain(forName: domain)
    return (defaults, domain)
  }
}
