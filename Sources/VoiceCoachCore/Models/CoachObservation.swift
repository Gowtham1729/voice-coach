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

  private enum CandidateKind: Int {
    case pause = 0
    case pitch = 1
  }

  private struct Candidate {
    let kind: CandidateKind
    let severity: Double
    let observation: CoachObservation
  }

  // MARK: - Content-frozen copy (exact)

  private static let pauseSummary =
    "Your pauses averaged longer than this take needs — especially mid-phrase."
  private static let pauseAction =
    "On the next take, aim for shorter gaps between phrases."

  private static let pitchSummary =
    "Your pitch stayed in a narrow range — the line sounds flat."
  private static let pitchAction =
    "On the next take, vary pitch more on the key words."

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
  public static func from(metrics: VoiceMetrics) -> CoachObservation? {
    var candidates: [Candidate] = []

    if metrics.internalPauseCount >= 2,
      !metrics.meanInternalPauseMs.isNaN,
      !metrics.meanInternalPauseMs.isInfinite,
      metrics.meanInternalPauseMs >= 700.0
    {
      let severity = (metrics.meanInternalPauseMs - 700.0) / 700.0
      candidates.append(
        Candidate(
          kind: .pause,
          severity: severity,
          observation: CoachObservation(
            eyebrow: "Insight",
            summary: pauseSummary,
            action: pauseAction
          )
        )
      )
    }

    if let pitchRange = metrics.pitchRangeSemitones,
      !pitchRange.isNaN,
      !pitchRange.isInfinite,
      pitchRange <= 3.0
    {
      let severity = (3.0 - max(0.0, pitchRange)) / 3.0
      candidates.append(
        Candidate(
          kind: .pitch,
          severity: severity,
          observation: CoachObservation(
            eyebrow: "Insight",
            summary: pitchSummary,
            action: pitchAction
          )
        )
      )
    }

    guard !candidates.isEmpty else { return nil }

    let best = candidates.max { a, b in
      if a.severity != b.severity {
        return a.severity < b.severity
      }
      // Tie-break: pause (0) > pitch (1)
      return a.kind.rawValue > b.kind.rawValue
    }

    return best?.observation
  }
}

/// Content-frozen copy parked for a later *conditional* phrase-end rule.
/// Not selected by `CoachObservation.from` — normal boundary decay is not an error.
public enum ParkedCoachObservationCopy {
  public static let phraseEndSummary = "Your energy dropped at the phrase end."
  public static let phraseEndAction =
    "On the next take, keep the last words as strong as the start."
}
