import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  func coachingPlan(for take: PracticeSession, in session: CoachingSession) -> CoachingPlan {
    let earlierTakes = session.takes.prefix { $0.id != take.id }
    if let reference = session.mimicReference?.take {
      let style = session.mimicAttemptStyles?[take.id] ?? session.mimicStyle
      let comparablePrevious = earlierTakes.last { prior in
        (session.mimicAttemptStyles?[prior.id] ?? session.mimicStyle) == style
      }
      return CoachingPlanner.mimic(
        reference: reference, attempt: take, previous: comparablePrevious,
        pinnedTarget: take.savedTarget)
    }
    let base = CoachingPlanner.recording(current: take.result.metrics)
    return CoachingPlan(
      notice: base.notice,
      plainTakeCue: take.transcription.flatMap {
        CoachingPlanner.plainTakeCue(
          words: $0.words, takeDuration: take.result.metrics.duration)
      })
  }

  func dismissRetryCard(for takeID: UUID) { dismissedRetryCardTakeIDs.insert(takeID) }

  func skipRetryCard(for takeID: UUID) { skippedRetryCardTakeIDs.insert(takeID) }

  func showRetryCard(for takeID: UUID) { skippedRetryCardTakeIDs.remove(takeID) }

  func tryAgain(take: PracticeSession, in session: CoachingSession) {
    let plan = coachingPlan(for: take, in: session)
    if session.isMimic, let focus = plan.focus {
      let style = session.mimicAttemptStyles?[take.id] ?? session.mimicStyle
      if let style, session.mimicStyle != style { updateMimicStyle(style) }
      let evaluation = plan.retryEvaluation
      let nextGap = evaluation?.verdict == .unreliable ? nil : evaluation?.newGap
      let current = TargetFocus(
        referenceWordIndex: focus.referenceWordIndex, word: focus.word,
        kind: focus.kind, gap: nextGap ?? focus.gap,
        referenceRange: focus.referenceRange,
        takeRange: evaluation?.newTakeRange ?? focus.takeRange,
        isPhrase: focus.isPhrase)
      pendingRetryTarget = (
        session.id, style, current)
      if let path = ProcessInfo.processInfo.environment["VOICECOACH_INJECT_TAKE"], !path.isEmpty {
        injectTakeFromEnvironment()
      } else {
        startMimicPractice()
      }
    } else if let path = ProcessInfo.processInfo.environment["VOICECOACH_INJECT_TAKE"], !path.isEmpty {
      injectTakeFromEnvironment()
    } else {
      recordAnother()
    }
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
