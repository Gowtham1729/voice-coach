import SwiftUI
import VoiceCoachCore

/// Exactly two measured practice targets, followed by the unmodified metrics stack.
struct TakeInsightsView: View {
  @EnvironmentObject private var model: AppModel
  @AppStorage(InsightWordingPreference.storageKey) private var wordingEnabled =
    InsightWordingPreference.default

  let takeID: UUID
  let metrics: VoiceMetrics
  let plan: CoachingPlan

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      SectionEyebrow(text: "Insights · practice next")
      if let limitation = plan.limitation {
        Text(limitation)
          .font(.caption)
          .foregroundStyle(Studio.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      ForEach(Array(plan.signals.enumerated()), id: \.element.id) { index, signal in
        if index > 0 { Divider() }
        signalRow(signal, number: index + 1)
      }
      Divider()
      InspectorMetricStack(metrics: InspectorMetricItem.voiceMetrics(metrics))
    }
    .task(id: "\(takeID.uuidString)-\(wordingEnabled)-\(plan.signals.map(\.id).joined())") {
      model.scheduleInsightWording(for: plan, takeID: takeID)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Practice signals and metrics")
  }

  private func signalRow(_ signal: CoachingSignal, number: Int) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(String(format: "%02d", number))
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(Studio.accent)
        .frame(width: 22, alignment: .leading)
      VStack(alignment: .leading, spacing: 5) {
        Text(signal.title)
          .font(.callout.weight(.semibold))
          .foregroundStyle(Studio.ink)
        Text(signal.observation)
          .font(.caption)
          .foregroundStyle(Studio.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Text(model.displayedAction(for: signal, takeID: takeID))
          .font(.callout)
          .foregroundStyle(Studio.ink)
          .fixedSize(horizontal: false, vertical: true)
        if let progress = signal.progress {
          Text(progress)
            .font(.caption)
            .foregroundStyle(Studio.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}
