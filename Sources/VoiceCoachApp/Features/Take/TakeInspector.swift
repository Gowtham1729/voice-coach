import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

struct TakeInspector: View {
  @EnvironmentObject private var model: AppModel
  @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmBeforeDelete = true
  @State private var takePendingDelete: UUID?

  var body: some View {
    Group {
      if let session = model.selectedSession, let take = model.selectedTake {
        InspectorShell {
          InspectorHeader(
            eyebrow: "Take",
            title: "Take \(takeNumber(take, in: session))",
            meta: takeMeta(session: session, take: take)
          ) {
            InspectorTakePager(session: session)
          }
        } content: {
          VStack(alignment: .leading, spacing: 14) {
            if !session.prompt.isEmpty {
              SectionEyebrow(text: "Prompt")
              Text(session.prompt)
                .font(.callout)
                .foregroundStyle(Studio.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            InspectorMetricStack(metrics: .voiceMetrics(take.result.metrics))
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
          takeFooter(take)
        }
        .modifier(
          DeleteTakeDialog(takeID: $takePendingDelete) { takeID in
            model.deleteTake(takeID)
          })
      }
    }
  }

  @ViewBuilder
  private func takeFooter(_ take: PracticeSession) -> some View {
    InspectorFooterStack {
      Button(action: model.copyAICoachPrompt) {
        Label("Copy coach notes", systemImage: "doc.on.doc")
          .inspectorActionLabel()
      }
      .studioGlassButton()
      .controlSize(.regular)
      .help("Copy notes to paste into a coach.")

      Button(action: model.exportCurrent) {
        Label("Export", systemImage: "square.and.arrow.up")
          .inspectorActionLabel()
      }
      .studioGlassButton()
      .controlSize(.regular)
      .help("Export the audio and report")

      HStack(spacing: 8) {
        Menu {
          Button("Copy Raw JSON", systemImage: "curlybraces", action: model.copyReport)
        } label: {
          Label("More", systemImage: "ellipsis")
            .inspectorActionLabel()
        }
        .menuStyle(.button)
        .studioGlassButton()

        Button(action: { requestDelete(take.id) }) {
          Label("Delete", systemImage: "trash")
            .inspectorActionLabel()
        }
        .tint(.red)
        .studioGlassButton()
        .disabled(model.isPlaying || model.isAnalyzing)
        .help("Delete")
      }
    }
  }

  private func takeMeta(session: CoachingSession, take: PracticeSession) -> [String] {
    var lines = [
      "\(session.name) · \(take.createdAt.formatted(date: .omitted, time: .shortened)) · \(vcNumber(take.result.metrics.duration, 1))s"
    ]
    if model.isSuggestingTitle {
      lines.append("Naming…")
    }
    return lines
  }

  private func takeNumber(_ take: PracticeSession, in session: CoachingSession) -> Int {
    (session.takes.firstIndex(where: { $0.id == take.id }) ?? 0) + 1
  }

  private func requestDelete(_ takeID: UUID) {
    if confirmBeforeDelete { takePendingDelete = takeID } else { model.deleteTake(takeID) }
  }
}
