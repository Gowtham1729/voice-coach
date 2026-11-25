import Foundation

/// The Sound comparison engines Ichido can list in Settings (D5, FR-23).
struct SoundEngineDescriptor: Identifiable, Equatable, Sendable {
  enum Tier: Sendable {
    /// Passed the full gate: listed in Settings → Transcription.
    case listed
    /// Passed the trust gates only: listed when Settings → Experiments allows it.
    case experimental
  }

  let id: String
  let name: String
  /// Shown before install (FR-24). Installed engines show their measured size. Binary units,
  /// matching the setup script and docs (126 MB, 519 MB).
  let approximateSizeBytes: Int
  let tier: Tier
  /// One short line on how it differs from the other engine.
  let summary: String

  /// No hosted download yet: engines are built on this Mac by the setup script.
  var installCommand: String { "./scripts/setup-sound-comparison.sh \(id)" }

  /// Whole binary megabytes, so a measured install reads like its estimate ("126 MB", not
  /// "125.9 MB") and like Parakeet's "714 MB".
  static func formattedSize(_ bytes: Int) -> String {
    let megabytes = Int((Double(bytes) / 1_048_576).rounded())
    return "\(megabytes.formatted()) MB"
  }
}

enum SoundEngineCatalog {
  /// Lab outcome (build/pron-lab/docs/02-eval-results.md): both engines passed the trust gates
  /// only, so both are experimental. Smallest first.
  static let all: [SoundEngineDescriptor] = [
    .init(id: "lite", name: "Lite", approximateSizeBytes: 126 << 20, tier: .experimental,
      summary: "Smaller and faster."),
    .init(id: "full", name: "Full", approximateSizeBytes: 519 << 20, tier: .experimental,
      summary: "Checks with three models, so it is slower."),
  ]

  static func descriptor(_ id: String) -> SoundEngineDescriptor? {
    all.first { $0.id == id }
  }

  /// Engines a person may see and use with the current Experiments setting.
  static func visible(showsExperimental: Bool) -> [SoundEngineDescriptor] {
    all.filter { $0.tier == .listed || showsExperimental }
  }
}

/// Settings → Experiments → Show experimental sound engines (FR-26). Off by default.
enum SoundEngineVisibilityPreference {
  static let storageKey = "voiceCoach.showExperimentalSoundEngines"

  static var isEnabled: Bool { UserDefaults.standard.bool(forKey: storageKey) }

  static func save(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: storageKey)
  }
}
