import SwiftUI
import VoiceCoachCore

struct SuggestedPracticeClipsView: View {
  let take: PracticeSession
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot
  @State private var selectedIDs: Set<Int> = []
  @State private var loadedClips: [SuggestedPracticeClip] = []

  private var clips: [SuggestedPracticeClip] {
    snapshot ? model.suggestedPracticeClips(for: take) : loadedClips
  }

  private var isBusy: Bool {
    model.isRecording || model.isAnalyzing || model.isRequestingPermission
      || model.mimicIsPreparing || model.isCapturingMimicReference
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        SectionEyebrow(text: "Suggested clips")
        Spacer()
        if !clips.isEmpty {
          Button(selectedIDs.count == clips.count ? "Deselect all" : "Select all") {
            selectedIDs = selectedIDs.count == clips.count ? [] : Set(clips.map(\.id))
          }
          .disabled(isBusy)
        }
      }

      if clips.isEmpty {
        Text("Clip suggestions need word timing. Re-transcribe, or choose a clip manually.")
          .font(.callout)
          .foregroundStyle(Studio.secondary)
      } else {
        Text("Choose phrases to repeat. Each selected clip becomes a practice session.")
          .font(.callout)
          .foregroundStyle(Studio.secondary)

        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(clips) { clip in
              clipRow(clip)
              if clip.id != clips.last?.id { Divider() }
            }
          }
          .padding(.trailing, 8)
        }
        .frame(height: min(280, CGFloat(clips.count) * 88))
        .accessibilityLabel("Suggested practice clips")
      }

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          creationControls
          Spacer()
          manualClipButton
        }
        VStack(alignment: .leading, spacing: 12) {
          creationControls
          manualClipButton
        }
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .studioCard()
    .onChange(of: take.transcription, initial: true) { _, _ in
      loadedClips = model.suggestedPracticeClips(for: take)
      selectedIDs = []
    }
  }

  private func clipRow(_ clip: SuggestedPracticeClip) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Toggle(isOn: Binding(
        get: { selectedIDs.contains(clip.id) },
        set: { selected in
          if selected { selectedIDs.insert(clip.id) } else { selectedIDs.remove(clip.id) }
        }
      )) {
        VStack(alignment: .leading, spacing: 5) {
          Text(clip.text)
            .font(.callout)
            .lineLimit(2)
            .help(clip.text)
          Text("\(vcNumber(clip.start, 1))–\(vcNumber(clip.end, 1))s · \(vcNumber(clip.duration, 1))s")
            .font(.caption.monospacedDigit())
            .foregroundStyle(Studio.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .toggleStyle(.checkbox)
      .disabled(isBusy)

      let isPreviewing = model.isPlaying && model.practiceClipPreviewID == clip.id
      Button {
        model.previewSuggestedPracticeClip(takeID: take.id, clipID: clip.id)
      } label: {
        Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.borderless)
      .disabled(isBusy)
      .help(isPreviewing ? "Stop clip" : "Preview clip")
      .accessibilityLabel(isPreviewing ? "Stop clip" : "Preview: \(clip.text)")
    }
  }

  @ViewBuilder
  private var creationControls: some View {
    if let progress = model.practiceClipCreationProgress {
      HStack(spacing: 10) {
        ProgressView().controlSize(.small)
        Text("Preparing clips · \(progress.completed) of \(progress.total)")
          .font(.callout)
          .foregroundStyle(Studio.secondary)
        Button("Cancel", action: model.cancelSuggestedPracticeCreation)
      }
    } else if !clips.isEmpty {
      Button(selectedIDs.count == 1 ? "Create practice session" : "Create \(selectedIDs.count) practice sessions") {
        model.createSuggestedPracticeSessions(takeID: take.id, clipIDs: selectedIDs)
      }
      .studioGlassButton(prominent: true)
      .disabled(selectedIDs.isEmpty || isBusy)
    }
  }

  private var manualClipButton: some View {
    Button("Choose a clip manually…", action: model.useCurrentRecordingAsMimicReference)
      .disabled(isBusy)
  }
}
