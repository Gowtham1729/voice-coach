import Foundation

/// Availability of the on-device wording model. Mapped from `SystemLanguageModel` in App.
public enum InsightCopyAvailability: Equatable, Sendable {
  case available
  case deviceNotEligible
  case appleIntelligenceNotEnabled
  case modelNotReady
  case unavailable
}

/// Structured rewrite payload. IDs stay in app code; the model only returns wording.
public struct InsightCopyRewrite: Equatable, Sendable {
  public let observation: String
  public let action: String

  public init(observation: String, action: String) {
    self.observation = observation
    self.action = action
  }
}

/// Optional on-device copy editor. Soft-fails to `nil`; the resolver maps that to frozen copy.
///
/// Gate 2: this API takes a `HeroPacket` only — never `VoiceMetrics`, transcript, or audio.
public protocol InsightCopyGenerating: Sendable {
  var availability: InsightCopyAvailability { get }
  func rewrite(_ packet: HeroPacket) async -> InsightCopyRewrite?
}

/// Fallback used when Apple Intelligence is absent (Linux SelfTest, unit tests, disabled Macs).
public struct UnavailableInsightCopyGenerator: InsightCopyGenerating {
  public init() {}
  public var availability: InsightCopyAvailability { .unavailable }
  public func rewrite(_: HeroPacket) async -> InsightCopyRewrite? { nil }
}
