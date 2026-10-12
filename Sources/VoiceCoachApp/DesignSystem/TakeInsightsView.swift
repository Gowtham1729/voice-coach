import SwiftUI
import VoiceCoachCore

/// Metrics for every take. Practice targets appear only for a Mimic comparison.
struct TakeInsightsView: View {
  let takeID: UUID
  let metrics: VoiceMetrics
  let plan: CoachingPlan

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      InspectorMetricStack(metrics: InspectorMetricItem.voiceMetrics(metrics))
      if let notice = plan.notice {
        noticeText(notice)
      }
      if let pause = plan.plainTakeCue {
        Divider()
        Text("Longest pause: \(vcNumber(pause.pauseDurationSeconds, 2)) s")
          .font(.caption)
          .foregroundStyle(Studio.secondary)
      }
      if let focus = plan.focus {
        Divider()
        Text("Target gap: \(vcNumber(plan.retryEvaluation?.newGap ?? focus.gap, 2)) \(unit(for: focus))")
          .font(.caption)
          .foregroundStyle(Studio.secondary)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Metrics")
  }

  private func unit(for focus: TargetFocus) -> String {
    switch focus.kind {
    case .pitch: "st"
    case .loudness: "dB"
    case .timing: "s"
    }
  }

  private func noticeText(_ notice: String) -> some View {
    Text(notice)
      .font(.caption)
      .foregroundStyle(Studio.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

}
