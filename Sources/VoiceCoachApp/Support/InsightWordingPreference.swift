import Foundation

/// Preference for optional on-device Insight wording rewrites.
/// Default is off when the key is unset (do not use raw `bool(forKey:)`).
enum InsightWordingPreference {
  static let storageKey = "voiceCoach.rewriteInsightWording"
  static let `default` = false

  static func load(defaults: UserDefaults = .standard) -> Bool {
    guard defaults.object(forKey: storageKey) != nil else { return `default` }
    return defaults.bool(forKey: storageKey)
  }

  static var isEnabled: Bool { load() }
}
