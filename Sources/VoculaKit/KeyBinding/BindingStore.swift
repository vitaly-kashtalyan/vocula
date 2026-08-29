import Foundation

public struct BindingStore: @unchecked Sendable {
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  public var primary: KeyBinding {
    get { decode("binding.primary") ?? .fn }
    set { encode(newValue, "binding.primary") }
  }

  public var languageCycle: KeyBinding {
    get { decode("binding.languageCycle") ?? .languageCycle }
    set { encode(newValue, "binding.languageCycle") }
  }

  public var config: GestureConfig {
    GestureConfig(primary: primary, languageCycle: languageCycle, timings: .default)
  }

  @discardableResult
  public mutating func save(primary newPrimary: KeyBinding) -> BindingVerdict {
    let verdict = BindingBlacklist.check(newPrimary)
    if case .rejected = verdict { return verdict }
    primary = newPrimary
    return verdict
  }

  @discardableResult
  public mutating func save(languageCycle newBinding: KeyBinding) -> BindingVerdict {
    let verdict = BindingBlacklist.check(newBinding)
    if case .rejected = verdict { return verdict }
    languageCycle = newBinding
    return verdict
  }

  private func decode(_ key: String) -> KeyBinding? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(KeyBinding.self, from: data)
  }

  private func encode(_ binding: KeyBinding, _ key: String) {
    guard let data = try? JSONEncoder().encode(binding) else { return }
    defaults.set(data, forKey: key)
  }
}
