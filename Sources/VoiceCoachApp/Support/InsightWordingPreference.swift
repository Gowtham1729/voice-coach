import Foundation

/// Preference for optional on-device exercise wording.
enum InsightWordingPreference {
  static let storageKey = "voiceCoach.rewriteInsightWording"
  static let `default` = true

  static func load(defaults: UserDefaults = .standard) -> Bool {
    guard defaults.object(forKey: storageKey) != nil else { return `default` }
    return defaults.bool(forKey: storageKey)
  }

  static var isEnabled: Bool { load() }
}
