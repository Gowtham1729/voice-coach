import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  func coachingPlan(for take: PracticeSession, in session: CoachingSession) -> CoachingPlan {
    let earlierTakes = session.takes.prefix { $0.id != take.id }
    let previous = earlierTakes.last
    if let reference = session.mimicReference?.take {
      let style = session.mimicAttemptStyles?[take.id] ?? session.mimicStyle
      let comparablePrevious = earlierTakes.last { prior in
        (session.mimicAttemptStyles?[prior.id] ?? session.mimicStyle) == style
      }
      return CoachingPlanner.mimic(
        reference: reference, attempt: take, previous: comparablePrevious)
    }
    // Different ordinary recordings are not assumed to be the same exercise.
    let comparablePrevious = session.isRetryStack && !session.trimmedPrompt.isEmpty
      ? previous?.result.metrics : nil
    return CoachingPlanner.recording(
      current: take.result.metrics, previous: comparablePrevious)
  }

  func displayedAction(for signal: CoachingSignal, takeID: UUID) -> String {
    guard InsightWordingPreference.isEnabled else { return signal.action }
    return insightActionOverrides[actionKey(for: signal, takeID: takeID)] ?? signal.action
  }

  func scheduleInsightWording(for plan: CoachingPlan, takeID: UUID) {
    guard InsightWordingPreference.isEnabled, plan.signals.count == 2 else { return }
    let key = planKey(for: plan, takeID: takeID)
    guard !insightAttemptedKeys.contains(key) else { return }
    insightAttemptedKeys.insert(key)

    Task.detached(priority: .utility) { [weak self] in
      let rewrites = await CoachingWordingGenerator().rewriteActions(for: plan)
      await MainActor.run {
        guard let self, let rewrites else { return }
        for (signal, rewrite) in zip(plan.signals, rewrites) {
          self.insightActionOverrides[self.actionKey(for: signal, takeID: takeID)] = rewrite
        }
      }
    }
  }

  func rescheduleInsightWordingForSelection() {
    guard let take = selectedTake, let session = selectedSession else { return }
    let plan = coachingPlan(for: take, in: session)
    insightAttemptedKeys.remove(planKey(for: plan, takeID: take.id))
    scheduleInsightWording(for: plan, takeID: take.id)
  }

  private func actionKey(for signal: CoachingSignal, takeID: UUID) -> String {
    "\(takeID.uuidString)|\(signal.id)|\(signal.action)"
  }

  private func planKey(for plan: CoachingPlan, takeID: UUID) -> String {
    "\(takeID.uuidString)|" + plan.signals.map { "\($0.id)|\($0.action)" }.joined(separator: "|")
  }
}
