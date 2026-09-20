import SwiftUI
import VoiceCoachCore

enum MimicMetric: String, CaseIterable, Identifiable {
  case pitch = "Pitch"
  case timing = "Timing"
  case emphasis = "Emphasis"
  var id: Self { self }
}

struct MimicComparisonView: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.studioSnapshot) var snapshot
  let reference: PracticeSession
  let attempt: PracticeSession
  let comparison: MimicComparison
  @State var metric: MimicMetric = .pitch
  @State var followPlayback = true
  @State var chartPosition = ScrollPosition(edge: .leading)

  init(
    reference: PracticeSession, attempt: PracticeSession, comparison: MimicComparison,
    initialMetric: String = "Pitch"
  ) {
    self.reference = reference
    self.attempt = attempt
    self.comparison = comparison
    _metric = State(initialValue: MimicMetric(rawValue: initialMetric) ?? .pitch)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 16) {
        SectionEyebrow(text: "Words")
        transcriptRow(
          "Reference", transcription: reference.transcription, color: .cyan, source: .reference)
        transcriptRow(
          "You", transcription: attempt.transcription, color: Studio.accent, source: .attempt)
      }
      .padding(18)
      .desktopPanel()

      if comparison.correspondenceReliable {
        VStack(alignment: .leading, spacing: 14) {
          HStack(spacing: 12) {
            SectionEyebrow(text: "Analysis")
            Spacer()
            if !snapshot {
              Toggle("Follow", isOn: $followPlayback)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Keep the playhead in view")
            }
            if snapshot {
              Text(metric.rawValue)
                .font(.caption.weight(.semibold))
            } else {
              Picker("Metric", selection: $metric) {
                ForEach(MimicMetric.allCases) { metric in Text(metric.rawValue).tag(metric) }
              }
              .pickerStyle(.segmented)
              .labelsHidden()
              .tint(.primary)
              .frame(maxWidth: 280)
            }
          }
          Text(chartCaption)
            .font(.caption)
            .foregroundStyle(Studio.secondary)

          if snapshot {
            chartContents
              .frame(height: chartHeight)
              .clipped()
          } else {
            GeometryReader { geometry in
              followableChart(viewportWidth: geometry.size.width)
            }
            .frame(height: chartHeight)
          }
          if metric != .timing {
            HStack(spacing: 14) {
              MimicSeriesLegendItem(title: "Reference", color: .cyan, dashed: true)
              MimicSeriesLegendItem(title: "You", color: Studio.accent, dashed: false)
            }
            .font(.caption)
            .accessibilityLabel("Dashed cyan: reference. Solid blue: you.")
          }
        }
        .padding(18)
        .studioCard()
      }
    }
  }
}
