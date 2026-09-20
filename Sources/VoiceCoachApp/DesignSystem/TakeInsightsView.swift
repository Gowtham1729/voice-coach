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
struct TakeInsightsView: View {
  let metrics: VoiceMetrics
  var observation: CoachObservation?

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
  }
}
