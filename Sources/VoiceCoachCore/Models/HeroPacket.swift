import Foundation

/// Version of the closed claim/action table + validator policy.
/// Bump when frozen copy, IDs, deny-list, or axis rules change so the wording cache misses.
public enum InsightCopyPolicy: Sendable {
  public static let version = 1
}

/// Selected coaching axis. The LM must not choose this; DSP + hero policy already did.
public enum CoachingHeroAxis: String, Sendable, Equatable, CaseIterable {
  case pause
  case pitch
}

/// Closed claim identifier. New heroes require a catalog entry, not a model invention.
public struct CoachingClaimID: RawRepresentable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let pauseLongMidPhrase = CoachingClaimID(rawValue: "pause.long_mid_phrase")
  public static let pitchNarrowRange = CoachingClaimID(rawValue: "pitch.narrow_range")
}

/// Closed next-take action identifier paired with a claim in `FrozenHeroCatalog`.
public struct CoachingActionID: RawRepresentable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let pauseShortenPhraseGaps = CoachingActionID(rawValue: "pause.shorten_phrase_gaps")
  public static let pitchVaryKeyWords = CoachingActionID(rawValue: "pitch.vary_key_words")
}

/// Closed pause/pitch proposition table. Gate 0 requires a packet to match a row.
public struct FrozenHeroDefinition: Equatable, Sendable {
  public let axis: CoachingHeroAxis
  public let claimID: CoachingClaimID
  public let actionID: CoachingActionID
  public let observation: String
  public let action: String

  public func packet(copyPolicyVersion: Int = InsightCopyPolicy.version) -> HeroPacket {
    HeroPacket(
      axis: axis,
      claimID: claimID,
      actionID: actionID,
      canonicalObservation: observation,
      canonicalAction: action,
      frozen: CoachObservation(summary: observation, action: action),
      copyPolicyVersion: copyPolicyVersion
    )
  }
}

public enum FrozenHeroCatalog: Sendable {
  public static let pause = FrozenHeroDefinition(
    axis: .pause,
    claimID: .pauseLongMidPhrase,
    actionID: .pauseShortenPhraseGaps,
    observation: FrozenCoachCopy.pauseSummary,
    action: FrozenCoachCopy.pauseAction
  )

  public static let pitch = FrozenHeroDefinition(
    axis: .pitch,
    claimID: .pitchNarrowRange,
    actionID: .pitchVaryKeyWords,
    observation: FrozenCoachCopy.pitchSummary,
    action: FrozenCoachCopy.pitchAction
  )

  public static let all: [FrozenHeroDefinition] = [pause, pitch]

  public static func definition(
    claimID: CoachingClaimID,
    actionID: CoachingActionID
  ) -> FrozenHeroDefinition? {
    all.first { $0.claimID == claimID && $0.actionID == actionID }
  }
}

/// Symbolic coaching proposition already selected by deterministic policy.
/// This is the only evidence an Insight wording model may see — never raw `VoiceMetrics`.
public struct HeroPacket: Equatable, Sendable {
  public let axis: CoachingHeroAxis
  public let claimID: CoachingClaimID
  public let actionID: CoachingActionID
  public let canonicalObservation: String
  public let canonicalAction: String
  public let frozen: CoachObservation
  public let copyPolicyVersion: Int

  public init(
    axis: CoachingHeroAxis,
    claimID: CoachingClaimID,
    actionID: CoachingActionID,
    canonicalObservation: String,
    canonicalAction: String,
    frozen: CoachObservation,
    copyPolicyVersion: Int = InsightCopyPolicy.version
  ) {
    self.axis = axis
    self.claimID = claimID
    self.actionID = actionID
    self.canonicalObservation = canonicalObservation
    self.canonicalAction = canonicalAction
    self.frozen = frozen
    self.copyPolicyVersion = copyPolicyVersion
  }

  /// Gate 0: IDs, axis, and canonical strings must match the frozen table.
  public var isValid: Bool {
    guard copyPolicyVersion == InsightCopyPolicy.version else { return false }
    guard let definition = FrozenHeroCatalog.definition(claimID: claimID, actionID: actionID)
    else { return false }
    return axis == definition.axis
      && canonicalObservation == definition.observation
      && canonicalAction == definition.action
      && frozen.summary == definition.observation
      && frozen.action == definition.action
      && frozen.eyebrow == "Insight"
  }

  public func cacheKey(locale: String) -> InsightCopyCacheKey {
    InsightCopyCacheKey(
      claimID: claimID.rawValue,
      actionID: actionID.rawValue,
      locale: locale,
      copyPolicyVersion: copyPolicyVersion
    )
  }

  /// Same hero policy as `CoachObservation.from` — pause/pitch only, pause-over-pitch ties.
  public static func from(metrics: VoiceMetrics) -> HeroPacket? {
    var candidates: [Candidate] = []

    if metrics.internalPauseCount >= 2,
      !metrics.meanInternalPauseMs.isNaN,
      !metrics.meanInternalPauseMs.isInfinite,
      metrics.meanInternalPauseMs >= 700.0
    {
      let severity = (metrics.meanInternalPauseMs - 700.0) / 700.0
      candidates.append(
        Candidate(axis: .pause, severity: severity, packet: FrozenHeroCatalog.pause.packet())
      )
    }

    if let pitchRange = metrics.pitchRangeSemitones,
      !pitchRange.isNaN,
      !pitchRange.isInfinite,
      pitchRange <= 3.0
    {
      let severity = (3.0 - max(0.0, pitchRange)) / 3.0
      candidates.append(
        Candidate(axis: .pitch, severity: severity, packet: FrozenHeroCatalog.pitch.packet())
      )
    }

    guard !candidates.isEmpty else { return nil }

    let best = candidates.max { a, b in
      if a.severity != b.severity {
        return a.severity < b.severity
      }
      return a.axis.heroRank > b.axis.heroRank
    }
    return best?.packet
  }
}

extension CoachingHeroAxis {
  /// Lower ranks win ties. Pause (0) beats pitch (1).
  fileprivate var heroRank: Int {
    switch self {
    case .pause: 0
    case .pitch: 1
    }
  }
}

private struct Candidate {
  let axis: CoachingHeroAxis
  let severity: Double
  let packet: HeroPacket
}
