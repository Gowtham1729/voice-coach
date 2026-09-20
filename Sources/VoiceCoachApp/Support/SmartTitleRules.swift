import Foundation

/// Preference for deferred on-device titles from transcripts.
/// Default is off when the key is unset (do not use raw `bool(forKey:)`).
enum AutoTitlePreference {
  static let storageKey = "voiceCoach.autoGenerateTitles"
  static let `default` = false

  static func load(defaults: UserDefaults = .standard) -> Bool {
    guard defaults.object(forKey: storageKey) != nil else { return `default` }
    return defaults.bool(forKey: storageKey)
  }

  static var isEnabled: Bool { load() }
}

/// Transcript / title sanitizing without importing FoundationModels (keeps analyze path light).
