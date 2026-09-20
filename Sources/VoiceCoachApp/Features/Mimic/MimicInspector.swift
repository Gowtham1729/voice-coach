import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

struct MimicInspector: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Group {
      if let session = model.selectedSession, let reference = session.mimicReference {
        if model.mimicWorkspaceMode == .compare, let take = model.selectedTake {
          compareInspector(session: session, reference: reference, take: take)
        } else {
          practiceInspector(session: session, reference: reference)
        }
      }
    }
  }

  @ViewBuilder
  private func compareInspector(
    session: CoachingSession, reference: MimicReference, take: PracticeSession
  ) -> some View {
    let takeNumber = (session.takes.firstIndex(where: { $0.id == take.id }) ?? 0) + 1
    let attemptStyle =
      session.mimicAttemptStyles?[take.id] ?? session.mimicStyle ?? .listenAndRepeat
    let metrics = take.result.metrics

    InspectorShell {
      InspectorHeader(
        eyebrow: "Comparison",
        title: "Take \(takeNumber)",
        meta: [
          "\(session.name) · \(attemptStyle.title) · \(vcNumber(metrics.duration, 1))s",
          "Reference · \(reference.sourceName) · \(vcNumber(reference.take.result.metrics.duration, 1))s",
        ]
      ) {
        InspectorTakePager(session: session)
      }
    } content: {
      VStack(alignment: .leading, spacing: 14) {
        InspectorMetricStack(metrics: InspectorMetricItem.voiceMetrics(metrics))

        if !model.mimicCompareAlignmentReliable {
          Text("Word comparison is limited. Coach notes use recording metrics.")
            .font(.caption)
            .foregroundStyle(Studio.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } footer: {
      InspectorFooterStack {
        Button {
          model.startMimicPractice()
        } label: {
          Text("Try Again")
            .inspectorActionLabel()
        }
        .studioGlassButton(prominent: true)
        .controlSize(.regular)
        .disabled(model.isPlaying || model.isAnalyzing)

        Button(action: model.copyMimicCoachPrompt) {
          Label("Copy coach notes", systemImage: "doc.on.doc")
            .inspectorActionLabel()
        }
        .studioGlassButton()
        .controlSize(.regular)
        .help("Copy notes to paste into a coach.")

        Menu {
          Button("Copy Raw JSON", systemImage: "curlybraces", action: model.copyMimicCompareJSON)
        } label: {
          Label("More", systemImage: "ellipsis")
            .inspectorActionLabel()
        }
        .menuStyle(.button)
        .studioGlassButton()
      }
    }
  }

  @ViewBuilder
  private func practiceInspector(session: CoachingSession, reference: MimicReference) -> some View {
    InspectorShell {
      InspectorHeader(
        eyebrow: model.mimicWorkspaceMode.inspectorTitle,
        title: session.name,
        meta: [
          "Reference · \(reference.sourceName) · \(vcDuration(reference.take.result.metrics.duration))"
        ]
      )
    } content: {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Microphone")
            .font(.callout)
          LiveMeterView(level: model.liveLevel).frame(height: 18)
          Text("2-second count-in before recording.")
            .font(.caption)
            .foregroundStyle(Studio.secondary)
        }

        Divider()

        VStack(alignment: .leading, spacing: 8) {
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
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
