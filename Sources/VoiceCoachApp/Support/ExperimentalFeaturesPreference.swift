import Foundation

enum ExperimentalFeaturesPreference {
  static let storageKey = "voiceCoach.experimentalFeatures"
  static let `default` = false

  static var isEnabled: Bool {
    UserDefaults.standard.bool(forKey: storageKey)
  }
}
