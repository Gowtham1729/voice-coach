import Foundation

/// Cache key for an accepted Insight rewrite. Churn is keyed to claim/action, not take audio.
public struct InsightCopyCacheKey: Hashable, Sendable {
  public let claimID: String
  public let actionID: String
  public let locale: String
  public let copyPolicyVersion: Int

  public init(claimID: String, actionID: String, locale: String, copyPolicyVersion: Int) {
    self.claimID = claimID
    self.actionID = actionID
    self.locale = locale
    self.copyPolicyVersion = copyPolicyVersion
  }

  public var storageKey: String {
    "voiceCoach.insightCopy.\(claimID).\(actionID).\(locale).v\(copyPolicyVersion)"
  }
}

public protocol InsightCopyCaching: Sendable {
  func observation(for key: InsightCopyCacheKey) -> CoachObservation?
  func store(_ observation: CoachObservation, for key: InsightCopyCacheKey)
}

/// Process-local cache. App may wrap this with UserDefaults for cross-launch stability.
public final class InMemoryInsightCopyCache: InsightCopyCaching, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [InsightCopyCacheKey: CoachObservation] = [:]

  public init() {}

  public func observation(for key: InsightCopyCacheKey) -> CoachObservation? {
    lock.lock()
    defer { lock.unlock() }
    return storage[key]
  }

  public func store(_ observation: CoachObservation, for key: InsightCopyCacheKey) {
    lock.lock()
    defer { lock.unlock() }
    storage[key] = observation
  }
}
