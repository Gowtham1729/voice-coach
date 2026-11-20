import SwiftUI
import VoiceCoachCore

enum VoiceMetricCopy {
  static let pitchRange = "Pitch range"
  static let phraseFade = "Loudness at phrase end"
  static let clarity = "Clarity"
  static let pauses = "Pauses"
}

/// One plain word under each number, so people can read it without knowing the unit.
/// Descriptive only: none of these says what is good or bad.
enum VoiceMetricWords {
  static func pitchRange(_ semitones: Double) -> String {
    semitones < 3 ? "narrow" : semitones < 7 ? "moderate" : "wide"
  }

  /// `endMinusStart` is the end of the phrase minus its start, in dB.
  static func phraseEnd(_ endMinusStart: Double) -> String {
    abs(endMinusStart) < 1.5 ? "steady" : endMinusStart < 0 ? "ends softer" : "ends louder"
  }

  static func clarity(_ hnr: Double) -> String {
    hnr < 7 ? "low" : hnr < 15 ? "medium" : "high"
  }
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
        detail: metrics.pitchRangeSemitones.map(VoiceMetricWords.pitchRange),
        symbol: "waveform.path"
      ),
      InspectorMetricItem(
        id: "phraseFade",
        title: VoiceMetricCopy.phraseFade,
        value: vcSigned(metrics.phraseDecayDB),
        unit: "dB",
        detail: VoiceMetricWords.phraseEnd(metrics.phraseDecayDB),
        symbol: "arrow.down.right"
      ),
      InspectorMetricItem(
        id: "clarity",
        title: VoiceMetricCopy.clarity,
        value: vcOptional(metrics.hnrDB),
        unit: "dB",
        detail: metrics.hnrDB.map(VoiceMetricWords.clarity),
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .font(.callout.weight(.medium))
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
    .animation(StudioMotion.quick(reduceMotion: reduceMotion), value: metric.value)
  }

  private var accessibilityLabel: String {
    if let detail = metric.detail {
      return "\(metric.title), \(metric.value) \(metric.unit), \(detail)"
    }
    return "\(metric.title), \(metric.value) \(metric.unit)"
  }
}
