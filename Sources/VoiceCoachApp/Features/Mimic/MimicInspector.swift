import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

struct MimicInspector: View {
  @EnvironmentObject private var model: AppModel
  @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmBeforeDelete = true
  @State private var takePendingDelete: UUID?

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
        TakeInsightsView(
          takeID: take.id,
          metrics: metrics,
          plan: model.coachingPlan(for: take, in: session)
        )
        MimicSoundsSection(session: session, reference: reference.take, take: take)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } footer: {
      InspectorFooterStack {
        HStack(spacing: 8) {
          // Report exports are for debugging analysis, so they stay behind Experiments.
          if model.showsExperimentalAsk {
            Menu {
              Button("Copy AI analysis prompt + JSON", systemImage: "doc.on.doc", action: model.copyMimicAIAnalysisPrompt)
                .help("Copies instructions and the comparison JSON. Ichido does not send it.")
              Button("Copy report JSON", systemImage: "curlybraces", action: model.copyMimicCompareJSON)
            } label: {
              Image(systemName: "ellipsis")
                .inspectorActionLabel()
                .accessibilityLabel("More")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .studioGlassButton()
            .help("More")
            .accessibilityLabel("More actions")
          }

          Button(action: model.exportCurrent) {
            Label(TakeScreenCopy.export, systemImage: "square.and.arrow.up")
              .inspectorActionLabel()
          }
          .studioGlassButton()
          .layoutPriority(1)
          .disabled(model.isRecording || model.isAnalyzing)
          .help("Export the audio and report")

          Button(role: .destructive, action: { requestDelete(take.id) }) {
            Image(systemName: "trash")
              .accessibilityLabel("Delete take")
          }
          .studioGlassButton()
          // Neutral, so the one filled control in the footer is never Delete.
          .tint(.secondary)
          .disabled(model.isPlaying || model.isAnalyzing || model.isRecording)
          .help("Delete this take. The reference and other takes stay.")
        }
      }
    }
    .modifier(
      DeleteTakeDialog(
        takeID: $takePendingDelete,
        title: "Delete this take?",
        message: "This take and its analysis will be deleted. The reference and other takes stay."
      ) { takeID in
        deleteTake(takeID, in: session)
      })
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
          Slider(value: $model.mimicReferenceVolume, in: 0.1...1) { Text("Reference volume") }
            .labelsHidden()
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

  private func requestDelete(_ takeID: UUID) {
    if confirmBeforeDelete {
      takePendingDelete = takeID
    } else if let session = model.selectedSession {
      deleteTake(takeID, in: session)
    }
  }

  private func deleteTake(_ takeID: UUID, in session: CoachingSession) {
    model.deleteTake(sessionID: session.id, takeID: takeID)
  }
}
