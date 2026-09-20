import SwiftUI
import VoiceCoachCore

enum VoiceMetricCopy {
  static let pitchRange = "Pitch range"
  static let phraseFade = "Drop at phrase end"
  static let clarity = "Clarity"
  static let pauses = "Pauses"
}

struct InspectorMetricItem: Identifiable {
  let id: String
  let title: String
  let value: String
  let unit: String
  var detail: String? = nil
  let symbol: String
}

extension InspectorMetricItem {
  static func voiceMetrics(_ metrics: VoiceMetrics) -> [InspectorMetricItem] {
    [
      InspectorMetricItem(
        id: "pitchRange",
        title: VoiceMetricCopy.pitchRange,
        value: vcOptional(metrics.pitchRangeSemitones),
        unit: "st",
        symbol: "waveform.path"
      ),
      InspectorMetricItem(
        id: "phraseFade",
        title: VoiceMetricCopy.phraseFade,
        value: vcSigned(metrics.phraseDecayDB),
        unit: "dB",
        symbol: "arrow.down.right"
      ),
      InspectorMetricItem(
        id: "clarity",
        title: VoiceMetricCopy.clarity,
        value: vcOptional(metrics.hnrDB),
        unit: "dB",
        symbol: "sparkles"
      ),
      InspectorMetricItem(
        id: "pauses",
        title: VoiceMetricCopy.pauses,
        value: "\(metrics.internalPauseCount)",
        unit: metrics.internalPauseCount == 1 ? "pause" : "pauses",
        detail: "\(vcNumber(metrics.meanInternalPauseMs, 0)) ms average",
        symbol: "pause.fill"
      ),
    ]
  }
}

struct InspectorMetricStack: View {
  let metrics: [InspectorMetricItem]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionEyebrow(text: "Metrics")
      VStack(spacing: 0) {
        ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
          InspectorMetricRow(metric: metric)
          if index < metrics.count - 1 {
            Divider()
              .padding(.leading, 34)
          }
        }
      }
      .desktopPanel()
    }
  }
}

struct InspectorMetricRow: View {
  let metric: InspectorMetricItem

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Label(metric.title, systemImage: metric.symbol)
        .font(.callout)
        .foregroundStyle(Studio.secondary)
        .labelStyle(.titleAndIcon)
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 1) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(metric.value)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .contentTransition(.numericText())
          Text(metric.unit)
            .font(.caption)
            .foregroundStyle(Studio.secondary)
        }
        if let detail = metric.detail {
          Text(detail)
            .font(.caption2)
            .foregroundStyle(Studio.secondary)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .animation(.smooth(duration: 0.22), value: metric.value)
  }

  private var accessibilityLabel: String {
    if let detail = metric.detail {
      return "\(metric.title), \(metric.value) \(metric.unit), \(detail)"
    }
    return "\(metric.title), \(metric.value) \(metric.unit)"
  }
}
