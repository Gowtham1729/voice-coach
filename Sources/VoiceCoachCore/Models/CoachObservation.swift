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

  /// Derives an actionable coaching observation from voice metrics.
  ///
  /// Conversational speech evidence rule:
  /// Typical inter-phrase conversational pauses range between 250–500 ms. When a take exhibits
  /// multiple internal pauses (count ≥ 2) with a mean pause duration ≥ 700 ms, the pauses
  /// noticeably disrupt speech momentum and conversational rhythm.
  ///
  /// In v1, this triggers the pause-primary insight hero. Other metric cases return nil
  /// (no pitch or clarity templates in v1) to keep metrics-first without filler.
  public static func from(metrics: VoiceMetrics) -> CoachObservation? {
    guard metrics.internalPauseCount >= 2,
      !metrics.meanInternalPauseMs.isNaN,
      !metrics.meanInternalPauseMs.isInfinite,
      metrics.meanInternalPauseMs >= 700.0
    else {
      return nil
    }

    return CoachObservation(
      eyebrow: "Insight",
      summary: "Your pauses averaged longer than this take needs — especially mid-phrase.",
      action: "On the next take, aim for shorter gaps between phrases."
    )
  }
}
