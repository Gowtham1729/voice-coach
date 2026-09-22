import Foundation
import VoiceCoachCore

extension AppModel {
  /// Sync Hybrid Insights copy. Nil only when no pause/pitch hero qualifies.
  /// Preference off / model miss / rejected rewrite → frozen catalog strings.
  func displayedInsight(for metrics: VoiceMetrics) -> CoachObservation? {
    _ = insightCopyRevision
    guard let packet = HeroPacket.from(metrics: metrics) else { return nil }
    let key = packet.cacheKey(locale: Locale.current.identifier)
    if let override = insightCopyByKey[key] {
      return override
    }
    if let persisted = insightResolverCache.observation(for: key) {
      return persisted
    }
    return packet.frozen
  }

  /// Optional on-device rewrite. No-ops when preference is off or no hero qualifies.
  /// Remembers attempts so fail-closed visits do not re-hit the model; use
  /// `rescheduleInsightWordingForSelection` after enabling the preference.
  func scheduleInsightWording(for metrics: VoiceMetrics) {
    guard InsightWordingPreference.isEnabled else { return }
    guard let packet = HeroPacket.from(metrics: metrics) else { return }
    let key = packet.cacheKey(locale: Locale.current.identifier)

    if insightCopyByKey[key] != nil { return }

    if let persisted = insightResolverCache.observation(for: key) {
      insightCopyByKey[key] = persisted
      insightCopyRevision += 1
      return
    }

    if insightAttemptedKeys.contains(key) || insightInFlightKeys.contains(key) {
      return
    }
    insightAttemptedKeys.insert(key)
    insightInFlightKeys.insert(key)

    let resolver = insightResolver
    Task.detached(priority: .utility) { [weak self] in
      let resolved = await resolver.resolve(packet: packet)
      await MainActor.run {
        guard let self else { return }
        self.insightInFlightKeys.remove(key)
        // Persist only accepted rewrites in memory; frozen stays the sync fallback.
        guard resolved != packet.frozen else { return }
        self.insightCopyByKey[key] = resolved
        self.insightCopyRevision += 1
      }
    }
  }

  func rescheduleInsightWordingForSelection() {
    guard let metrics = selectedTake?.result.metrics else { return }
    if let packet = HeroPacket.from(metrics: metrics) {
      let key = packet.cacheKey(locale: Locale.current.identifier)
      insightAttemptedKeys.remove(key)
      insightInFlightKeys.remove(key)
    }
    scheduleInsightWording(for: metrics)
  }
}
