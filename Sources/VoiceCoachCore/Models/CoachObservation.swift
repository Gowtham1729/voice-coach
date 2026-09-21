import Foundation

/// Primary coaching observation derived deterministically from objective voice metrics.
public struct CoachObservation: Equatable, Sendable {
  public let eyebrow: String
  public let summary: String
  public let action: String

  public init(
    eyebrow: String = "Insight",
    summary: String,
    action: String
  ) {
    self.eyebrow = eyebrow
    self.summary = summary
    self.action = action
  }

  /// Evaluates objective voice metrics and returns the single primary coaching observation
  /// with the highest relative severity. Returns nil if no hero-capable metric qualifies.
  ///
  /// Hero-capable (product lock): **pauses** + **pitch/prosody**. Clarity and phrase-end drop
  /// are not default heroes. Phrase-end Content strings stay in `ParkedCoachObservationCopy`
  /// for a later conditional rule (e.g. repeated fades across phrases).
  ///
  /// Threshold gates:
  /// 1. Pause (inter-phrase disruption): count ≥ 2 AND meanInternalPauseMs ≥ 700.0 ms
  ///    - Severity: (meanInternalPauseMs - 700.0) / 700.0
  /// 2. Pitch narrow (flat / monotone pitch contour): pitchRangeSemitones != nil AND ≤ 3.0 st
  ///    - Severity: (3.0 - range) / 3.0
  ///
  /// Ranking & tie-break: highest severity; ties prefer pause over pitch.
  ///
  /// This is the fail-closed Insight copy. An optional on-device wording layer may rewrite
  /// the selected `HeroPacket` and must fall back to these frozen strings on any reject.
  public static func from(metrics: VoiceMetrics) -> CoachObservation? {
    HeroPacket.from(metrics: metrics)?.frozen
  }
}

/// Content-frozen observation/action strings. Insight wording may paraphrase these
/// meanings only — it must not invent a new hero or claim.
public enum FrozenCoachCopy: Sendable {
  public static let pauseSummary =
    "Your pauses averaged longer than this take needs — especially mid-phrase."
  public static let pauseAction =
    "On the next take, aim for shorter gaps between phrases."

  public static let pitchSummary =
    "Your pitch stayed in a narrow range — the line sounds flat."
  public static let pitchAction =
    "On the next take, vary pitch more on the key words."
}

/// Content-frozen copy parked for a later *conditional* phrase-end rule.
/// Not selected by `CoachObservation.from` — normal boundary decay is not an error.
public enum ParkedCoachObservationCopy {
  public static let phraseEndSummary = "Your energy dropped at the phrase end."
  public static let phraseEndAction =
    "On the next take, keep the last words as strong as the start."
}
