import Foundation

/// Owns gates 0–9 for Insight wording. Fail-closed result is always frozen catalog copy
/// when a hero qualifies — never empty coaching, never a new claim.
public struct InsightCopyResolver: Sendable {
  private let generator: (any InsightCopyGenerating)?
  private let cache: any InsightCopyCaching
  private let localeIdentifier: @Sendable () -> String
  private let isEnabled: @Sendable () -> Bool

  public init(
    generator: (any InsightCopyGenerating)? = nil,
    cache: any InsightCopyCaching = InMemoryInsightCopyCache(),
    localeIdentifier: @escaping @Sendable () -> String = { "en" },
    isEnabled: @escaping @Sendable () -> Bool = { true }
  ) {
    self.generator = generator
    self.cache = cache
    self.localeIdentifier = localeIdentifier
    self.isEnabled = isEnabled
  }

  /// Nil only when no pause/pitch hero qualifies. Otherwise frozen or an accepted rewrite.
  public func resolve(metrics: VoiceMetrics) async -> CoachObservation? {
    guard let packet = HeroPacket.from(metrics: metrics) else { return nil }
    return await resolve(packet: packet)
  }

  public func resolve(packet: HeroPacket) async -> CoachObservation {
    // Gate 0 — broken policy never reaches the model.
    guard packet.isValid else { return packet.frozen }
    // Preference off → frozen (optional layer).
    guard isEnabled() else { return packet.frozen }

    let key = packet.cacheKey(locale: localeIdentifier())
    // Gate 9 — accepted rewrite is sticky across identical claim/action/locale/policy.
    if let cached = cache.observation(for: key) {
      return cached
    }

    // Gate 1 — unavailable / not ready / ineligible → frozen, no chrome.
    guard let generator, generator.availability == .available else {
      return packet.frozen
    }

    // Gate 2 — generator API is packet-only; prompt uses canonical strings only.
    // Gate 3 — App adapter returns @Generable {observation, action} as InsightCopyRewrite.
    // Gate 8 — nil / timeout / error → frozen.
    guard let rewrite = await generator.rewrite(packet) else {
      return packet.frozen
    }

    // Gates 4–7 — sanitize, deny-list, numbers, axis. Reject → frozen.
    guard let accepted = InsightCopyRules.acceptedObservation(rewrite: rewrite, packet: packet)
    else {
      return packet.frozen
    }

    cache.store(accepted, for: key)
    return accepted
  }
}
