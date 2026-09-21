import Foundation
import VoiceCoachCore

/// UserDefaults-backed cache of accepted Insight rewrites (gate 9, cross-launch).
final class PersistedInsightCopyCache: InsightCopyCaching, @unchecked Sendable {
  private let memory = InMemoryInsightCopyCache()
  private let defaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func observation(for key: InsightCopyCacheKey) -> CoachObservation? {
    if let cached = memory.observation(for: key) { return cached }
    guard let data = defaults.data(forKey: key.storageKey),
      let stored = try? decoder.decode(StoredInsightCopy.self, from: data)
    else { return nil }
    let observation = CoachObservation(summary: stored.summary, action: stored.action)
    memory.store(observation, for: key)
    return observation
  }

  func store(_ observation: CoachObservation, for key: InsightCopyCacheKey) {
    memory.store(observation, for: key)
    let stored = StoredInsightCopy(summary: observation.summary, action: observation.action)
    if let data = try? encoder.encode(stored) {
      defaults.set(data, forKey: key.storageKey)
    }
  }
}

private struct StoredInsightCopy: Codable {
  let summary: String
  let action: String
}
