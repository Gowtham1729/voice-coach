import Foundation
import VoiceCoachCore

extension AppModel {
  func displayedInsight(for metrics: VoiceMetrics) -> CoachObservation? {
    _ = insightCopyRevision
    guard let packet = HeroPacket.from(metrics: metrics) else { return nil }
    let key = packet.cacheKey(locale: Locale.current.identifier)
    return insightCopyByKey[key] ?? packet.frozen
  }

  func scheduleInsightWording(for metrics: VoiceMetrics) {
    guard InsightWordingPreference.isEnabled else { return }
    guard let packet = HeroPacket.from(metrics: metrics) else { return }
    let key = packet.cacheKey(locale: Locale.current.identifier)
    if insightCopyByKey[key] != nil { return }
    if insightAttemptedKeys.contains(key) { return }
    insightAttemptedKeys.insert(key)

    if let persisted = insightResolverCache.observation(for: key) {
      insightCopyByKey[key] = persisted
      insightCopyRevision += 1
      return
    }

    let resolver = insightResolver
    Task.detached(priority: .utility) { [weak self] in
      let resolved = await resolver.resolve(packet: packet)
      await MainActor.run {
        guard let self else { return }
        self.insightCopyByKey[key] = resolved
        self.insightCopyRevision += 1
      }
    }
  }
}
