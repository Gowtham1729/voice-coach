import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

struct MimicInspector: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    StudioScroll {
      if let session = model.selectedSession, let reference = session.mimicReference {
        if model.mimicWorkspaceMode == .compare, let take = model.selectedTake {
          compareInspector(session: session, reference: reference, take: take)
        } else {
          practiceInspector(session: session, reference: reference)
        }
      }
    }
    .scrollContentBackground(.hidden)
  }

  @ViewBuilder
  private func compareInspector(
    session: CoachingSession, reference: MimicReference, take: PracticeSession
  ) -> some View {
    let takeNumber = (session.takes.firstIndex(where: { $0.id == take.id }) ?? 0) + 1
    let attemptStyle =
      session.mimicAttemptStyles?[take.id] ?? session.mimicStyle ?? .listenAndRepeat
    let metrics = take.result.metrics

    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        SectionEyebrow(text: "Comparison")
        Text("Take \(takeNumber)")
          .font(.headline)
        Text("\(session.name) · \(attemptStyle.title) · \(vcNumber(metrics.duration, 1))s")
          .font(.caption)
          .foregroundStyle(Studio.secondary)
          .lineLimit(2)
        Text(
          "Reference · \(reference.sourceName) · \(vcNumber(reference.take.result.metrics.duration, 1))s"
        )
        .font(.caption)
        .foregroundStyle(Studio.secondary)
        .lineLimit(2)
      }

      Divider()

      InspectorMetricCard(
        title: VoiceMetricCopy.pitchRange, value: vcOptional(metrics.pitchRangeSemitones), unit: "st",
        symbol: "waveform.path")
      InspectorMetricCard(
        title: VoiceMetricCopy.phraseFade, value: vcSigned(metrics.phraseDecayDB), unit: "dB",
        symbol: "arrow.down.right")
      InspectorMetricCard(
        title: VoiceMetricCopy.clarity, value: vcOptional(metrics.hnrDB), unit: "dB",
        symbol: "sparkles")
      InspectorMetricCard(
        title: VoiceMetricCopy.pauses,
        value: "\(metrics.internalPauseCount)",
        unit: metrics.internalPauseCount == 1 ? "pause" : "pauses",
        detail: "\(vcNumber(metrics.meanInternalPauseMs, 0)) ms average",
        symbol: "pause.fill"
      )

      if !model.mimicCompareAlignmentReliable {
        Text("Word comparison is limited. Coach copy uses recording metrics.")
          .font(.caption)
          .foregroundStyle(Studio.secondary)
      }

      Divider()

      VStack(spacing: 8) {
        Button {
          model.startMimicPractice()
        } label: {
          Text("Practice")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(model.isPlaying || model.isAnalyzing)

        Button(action: model.copyMimicCoachPrompt) {
          Label("Copy for Coach", systemImage: "doc.on.doc")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help("Copy this comparison to paste into a coach.")

        Menu {
          Button("Copy Raw JSON", systemImage: "curlybraces", action: model.copyMimicCompareJSON)
        } label: {
          Label("More", systemImage: "ellipsis")
            .frame(maxWidth: .infinity)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
      }
    }
    .padding(16)
  }

  @ViewBuilder
  private func practiceInspector(session: CoachingSession, reference: MimicReference) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        SectionEyebrow(text: model.mimicWorkspaceMode.inspectorTitle)
        Text(session.name)
          .font(.headline)
          .lineLimit(2)
        Text(
          "Reference · \(reference.sourceName) · \(vcDuration(reference.take.result.metrics.duration))"
        )
        .font(.caption)
        .foregroundStyle(Studio.secondary)
        .lineLimit(2)
      }

      Divider()

      Text("Microphone")
        .font(.callout)
      LiveMeterView(level: model.liveLevel).frame(height: 18)
      Text("2-second count-in before recording.")
        .font(.caption)
        .foregroundStyle(Studio.secondary)

      Divider()

      Text("Reference volume")
        .font(.callout)
      Slider(value: $model.mimicReferenceVolume, in: 0.1...1)
      if session.mimicStyle == .speakAlong {
        Label(
          "Use headphones so the reference isn’t recorded.", systemImage: "headphones"
        )
        .font(.caption)
        .foregroundStyle(Studio.secondary)
      }
    }
    .padding(16)
  }
}
