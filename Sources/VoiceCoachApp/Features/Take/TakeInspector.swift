import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

struct TakeInspector: View {
  @EnvironmentObject private var model: AppModel
  @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmBeforeDelete = true
  @State private var takePendingDelete: UUID?

  var body: some View {
    StudioScroll {
      if let session = model.selectedSession, let take = model.selectedTake {
        VStack(alignment: .leading, spacing: 14) {
          VStack(alignment: .leading, spacing: 3) {
            SectionEyebrow(text: "Take")
            Text("Take \(takeNumber(take, in: session))")
              .font(.headline)
            Text(
              "\(session.name) · \(take.createdAt.formatted(date: .omitted, time: .shortened)) · \(vcNumber(take.result.metrics.duration, 1))s"
            )
            .font(.caption)
            .foregroundStyle(Studio.secondary)
            .lineLimit(2)
            if model.isSuggestingTitle {
              Text("Naming from transcript…")
                .font(.caption2)
                .foregroundStyle(Studio.secondary.opacity(0.85))
            }
          }

          Divider()

          if !session.prompt.isEmpty {
            SectionEyebrow(text: "Prompt")
            Text(session.prompt)
              .font(.callout)
              .foregroundStyle(Studio.secondary)
              .fixedSize(horizontal: false, vertical: true)

            Divider()
          }

          InspectorMetricCard(
            title: "Pitch Dynamic Range",
            value: vcOptional(take.result.metrics.pitchRangeSemitones), unit: "st",
            symbol: "waveform.path")
          InspectorMetricCard(
            title: "Trailing Energy Drop", value: vcSigned(take.result.metrics.phraseDecayDB),
            unit: "dB", symbol: "arrow.down.right")
          InspectorMetricCard(
            title: "Vocal Clarity (HNR)", value: vcOptional(take.result.metrics.hnrDB), unit: "dB",
            symbol: "sparkles")
          InspectorMetricCard(
            title: "Pause Cadence",
            value: "\(take.result.metrics.internalPauseCount)",
            unit: take.result.metrics.internalPauseCount == 1 ? "pause" : "pauses",
            detail: "\(vcNumber(take.result.metrics.meanInternalPauseMs, 0)) ms average",
            symbol: "pause.fill"
          )

          Divider()

          VStack(spacing: 8) {
            Button(action: model.copyAICoachPrompt) {
              Label("Copy Coach Prompt", systemImage: "doc.on.doc")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .help("Copy a prompt with this take’s measurements for an AI coach")

            Button(action: model.exportCurrent) {
              Label("Export Audio + JSON", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Export the recording and analysis files")

            HStack(spacing: 8) {
              Menu {
                Button("Copy Raw JSON", systemImage: "curlybraces", action: model.copyReport)
              } label: {
                Label("More", systemImage: "ellipsis")
                  .frame(maxWidth: .infinity)
              }
              .menuStyle(.button)
              .buttonStyle(.bordered)

              Button(action: { requestDelete(take.id) }) {
                Label("Delete", systemImage: "trash")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.bordered)
              .tint(.red)
              .disabled(model.isPlaying || model.isAnalyzing)
              .help("Delete this take")
            }
          }
        }
        .padding(16)
        .modifier(
          DeleteTakeDialog(takeID: $takePendingDelete) { takeID in
            model.deleteTake(takeID)
          })
      }
    }
    .scrollContentBackground(.hidden)
  }

  private func takeNumber(_ take: PracticeSession, in session: CoachingSession) -> Int {
    (session.takes.firstIndex(where: { $0.id == take.id }) ?? 0) + 1
  }

  private func requestDelete(_ takeID: UUID) {
    if confirmBeforeDelete { takePendingDelete = takeID } else { model.deleteTake(takeID) }
  }
}
