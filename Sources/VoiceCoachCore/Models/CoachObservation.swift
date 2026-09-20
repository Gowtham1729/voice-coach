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
    case phrase = 2
  }

  private struct Candidate {
    let kind: CandidateKind
    let severity: Double
    let observation: CoachObservation
  }

  /// Evaluates objective voice metrics against evidence-based gates and returns the single primary
  /// coaching observation with the highest relative severity. Returns nil if no metric qualifies.
  /// Clarity is currently parked and not evaluated.
  ///
  /// Threshold gates:
  /// 1. Pause (inter-phrase disruption): count ≥ 2 AND meanInternalPauseMs ≥ 700.0 ms
  ///    - Severity: (meanInternalPauseMs - 700.0) / 700.0
  /// 2. Pitch narrow (flat / monotone pitch contour): pitchRangeSemitones != nil AND ≤ 3.0 st
  ///    - Severity: (3.0 - range) / 3.0
  /// 3. Phrase-end drop (audibility decay / loss of energy on phrase tail): phraseDecayDB ≤ -4.0 dB
  ///    - Severity: ((-phraseDecayDB) - 4.0) / 4.0
  ///
  /// Ranking & Tie-breaking:
  /// Candidates are ranked by severity descending. If severities tie, stable precedence order is
  /// pause, then pitch, then phrase.
  public static func from(metrics: VoiceMetrics) -> CoachObservation? {
    var candidates: [Candidate] = []

    // 1. Pause candidate
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
            summary: "Your pauses averaged longer than this take needs — especially mid-phrase.",
            action: "On the next take, aim for shorter gaps between phrases."
          )
        )
      )
    }

    // 2. Pitch narrow candidate
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
            summary: "Your pitch stayed in a narrow range — the line sounds flat.",
            action: "On the next take, vary pitch more on the key words."
          )
        )
      )
    }

    // 3. Phrase-end drop candidate (phraseDecay = endDB - startDB; more negative = quieter ending)
    if !metrics.phraseDecayDB.isNaN,
      !metrics.phraseDecayDB.isInfinite,
      metrics.phraseDecayDB <= -4.0
    {
      let severity = ((-metrics.phraseDecayDB) - 4.0) / 4.0
      candidates.append(
        Candidate(
          kind: .phrase,
          severity: severity,
          observation: CoachObservation(
            eyebrow: "Insight",
            summary: "Your energy dropped at the phrase end.",
            action: "On the next take, keep the last words as strong as the start."
          )
        )
      )
    }

    guard !candidates.isEmpty else { return nil }

    let best = candidates.max { a, b in
      if a.severity != b.severity {
        return a.severity < b.severity
      }
      // Tie-break: pause (0) > pitch (1) > phrase (2)
      return a.kind.rawValue > b.kind.rawValue
    }

    return best?.observation
  }
}
