import Foundation

/// Canonical prompt for Insight wording. Built from a valid `HeroPacket` only.
public enum InsightCopyPrompt: Sendable {
  public static let instructions = """
    You rewrite approved voice-practice coaching copy.
    Keep the same meaning. Do not add facts, numbers, diagnoses, emotions, or new advice.
    Stay on the given topic. One observation and one next-take action.
    Neutral and concrete. No quotes. No markdown. No URLs.
    """

  /// User message for the wording model. Must not include raw acoustic metrics.
  public static func userMessage(for packet: HeroPacket) -> String {
    """
    Rewrite this \(packet.axis.rawValue) coaching pair. Same meaning only.

    Observation:
    \(packet.canonicalObservation)

    Action:
    \(packet.canonicalAction)
    """
  }
}
