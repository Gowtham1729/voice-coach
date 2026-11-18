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

            TakeInsightsView(
              takeID: take.id,
              metrics: take.result.metrics,
              plan: model.coachingPlan(for: take, in: session)
            )
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
          takeFooter(take)
        }
        .modifier(
          DeleteTakeDialog(
            takeID: $takePendingDelete,
            title: "Delete this take?",
            message: session.takeCount == 1
              ? "This is the only take, so the practice is deleted too, including its audio, transcript, and analysis."
              : "This take's audio, transcript, and analysis are deleted. The other takes stay."
          ) { takeID in
            deleteTake(takeID, in: session)
          })
      }
    }
  }

  @ViewBuilder
  private func takeFooter(_ take: PracticeSession) -> some View {
    let chrome = TakeActionChrome.plainTake()
    InspectorFooterStack {
      HStack(spacing: 8) {
        Menu {
          Button("Copy AI analysis prompt + JSON", systemImage: "doc.on.doc", action: model.copyAIAnalysisPrompt)
            .help("Copies instructions and this take's JSON. Ichido does not send it.")
          Button("Copy report JSON", systemImage: "curlybraces", action: model.copyReport)
        } label: {
          Image(systemName: "ellipsis")
            .inspectorActionLabel()
            .accessibilityLabel("More")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .studioGlassButton()
        .help("More")

        if chrome.exportSitsWithDelete {
          Button(action: model.exportCurrent) {
            Label(TakeScreenCopy.export, systemImage: "square.and.arrow.up")
              .inspectorActionLabel()
          }
          .studioGlassButton(prominent: chrome.isFilled(TakeScreenCopy.export))
          .controlSize(.regular)
          .help("Export the audio and report")
        }

        Button(role: .destructive, action: { requestDelete(take.id) }) {
          Label("Delete…", systemImage: "trash")
            .inspectorActionLabel()
        }
        .studioGlassButton()
        .disabled(model.isPlaying || model.isAnalyzing || model.isRecording)
        .help("Delete this take")
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
