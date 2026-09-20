import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

struct TakeView: View {
  /// When true, Mimic owns take selection chrome; this view supplies content + transport only.
  var embedded = false

  @EnvironmentObject var model: AppModel
  @Environment(\.studioSnapshot) var snapshot
  @Environment(\.accessibilityReduceMotion) var reduceMotion
  @State var selectedPlot: AnalysisPlot = .pitch
  @State var selectedWordIndex: Int?
  @State var isGraphCopied = false
  @State var isTranscriptCopied = false
  @State var isHandlingWordStep = false

  var body: some View {
    Group {
      if let session = model.selectedSession, let take = model.selectedTake {
        takeWorkspace(session, take: take)
      } else {
        StudioPage(maxWidth: 1050, horizontalPadding: 20) {
          EmptyState(
            icon: "waveform",
            title: "Recording not found",
            detail: "Choose another recording from your local library.",
            actionTitle: "View library"
          ) {
            model.navigate(to: .library)
          }
        }
      }
    }
  }

  func takeWorkspace(_ session: CoachingSession, take: PracticeSession) -> some View {
    VStack(spacing: 0) {
      StudioScroll {
        VStack(alignment: .leading, spacing: 14) {
          takeBar(session, take: take)
          transcriptCard(take)
          analysisCard(take)
        }
        .id(take.id)
        .transition(.opacity.combined(with: .scale(scale: 0.992, anchor: .top)))
        .animation(quickMotion, value: model.selectedTakeID)
        .frame(maxWidth: 1050, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, embedded ? 8 : 28)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .top)
      }
      .onChange(of: model.selectedTakeID) { _, _ in
        selectedWordIndex = nil
        isTranscriptCopied = false
      }
      .onChange(of: model.isPlaying) { _, playing in
        // Manual selection only anchors seek; once playback runs, follow the timeline.
        if playing { selectedWordIndex = nil }
      }

      stickyTransport(take)
    }
    .background(wordStepShortcuts(for: take))
  }

  func takeBar(_ session: CoachingSession, take: PracticeSession) -> some View {
    HStack(spacing: 12) {
      Label(take.takeSource.title, systemImage: take.takeSource.icon)
        .font(.callout.weight(.medium))

      Text(
        "\(take.createdAt.formatted(date: .omitted, time: .shortened)) · \(vcNumber(take.result.metrics.duration, 1))s"
      )
      .font(.caption)
      .foregroundStyle(Studio.secondary)

      Spacer()

      if embedded {
        Text("Take \(takeNumber(take, in: session)) of \(session.takeCount)")
          .font(.caption)
          .foregroundStyle(Studio.secondary)
      } else if snapshot {
        Text("Take \(takeNumber(take, in: session)) of \(session.takeCount)")
          .font(.caption)
          .padding(.horizontal, 10)
          .frame(height: 28)
          .background(Studio.surface, in: RoundedRectangle(cornerRadius: 6))
      } else {
        Picker(
          "Take",
          selection: Binding(
            get: { model.selectedTakeID ?? take.id },
            set: { takeID in model.selectTake(takeID) }
          )
        ) {
          ForEach(Array(session.takes.enumerated()), id: \.element.id) { index, item in
            Text("Take \(index + 1) of \(session.takeCount)").tag(item.id)
          }
        }
        .labelsHidden()
        .frame(width: 150)
      }

      if !embedded, !session.isMimic {
        if !snapshot, model.isRecording {
          LiveMeterView(level: model.liveLevel)
            .frame(width: 120)
          Text(vcDuration(model.elapsed))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Color.red)
            .frame(width: 56, alignment: .trailing)
          Button("Stop", action: model.recordButtonPressed)
            .tint(.red)
            .studioGlassButton(prominent: true)
            .disabled(model.isAnalyzing || model.isRequestingPermission)
            .accessibilityLabel("Stop recording")
        } else {
          Button("Record another", action: model.recordButtonPressed)
            .studioGlassButton(prominent: true)
            .disabled(model.isRecording || model.isAnalyzing || model.isRequestingPermission)
        }
      }
      if !embedded, take.takeSource != .recorded {
        Button("Use as Mimic") { model.useCurrentRecordingAsMimicReference() }
          .tint(.primary)
          .studioGlassButton()
          .disabled(model.isRecording || model.isAnalyzing)
      }
    }
    .frame(minHeight: 32)
  }
}
