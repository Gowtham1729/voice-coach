import SwiftUI
import VoiceCoachCore

/// Plain observation hero block displaying primary coaching feedback above metrics.
struct CoachObservationBlock: View {
  let observation: CoachObservation

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionEyebrow(text: observation.eyebrow)
      VStack(alignment: .leading, spacing: 8) {
        Text(observation.summary)
          .font(.callout)
          .foregroundStyle(Studio.ink)
          .fixedSize(horizontal: false, vertical: true)
        Text(observation.action)
          .font(.callout)
          .foregroundStyle(Studio.ink)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// Shared insights view used by TakeInspector and MimicInspector compare content
/// to maintain a synchronous visual hierarchy (Hero observation above quieter metrics stack).
///
/// Caller passes `displayedInsight` when the optional wording layer is wired. Metrics always
/// render. Missing / rejected wording uses frozen `CoachObservation` — same card, no AI chrome.
struct TakeInsightsView: View {
  let metrics: VoiceMetrics
  let observation: CoachObservation?

  init(metrics: VoiceMetrics, observation: CoachObservation? = nil) {
    self.metrics = metrics
    self.observation = observation ?? CoachObservation.from(metrics: metrics)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let observation {
        CoachObservationBlock(observation: observation)
      }
      InspectorMetricStack(metrics: InspectorMetricItem.voiceMetrics(metrics))
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Insights")
  }
}

extension View {
  /// Schedules optional Insight wording when the take or preference changes.
  func insightWordingTask(
    takeID: UUID,
    metrics: VoiceMetrics,
    wordingEnabled: Bool,
    schedule: @escaping (VoiceMetrics) -> Void
  ) -> some View {
    task(id: InsightWordingTaskID(takeID: takeID, wordingEnabled: wordingEnabled)) {
      schedule(metrics)
    }
  }
}

private struct InsightWordingTaskID: Hashable {
  let takeID: UUID
  let wordingEnabled: Bool
}
