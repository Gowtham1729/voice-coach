import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

struct CreateSessionView: View {
  @EnvironmentObject private var model: AppModel
  @State private var selectedIDs: Set<Int> = []
  @State private var chooseManually = false
  @State private var excerptStart = 0.0
  @State private var excerptEnd = 0.0

  private var usesManualSelection: Bool {
    chooseManually || model.suggestedPracticeClips.isEmpty
  }

  private var canCreate: Bool {
    model.mimicDraft != nil && !model.mimicIsPreparing && !model.isCapturingMimicReference
      && (usesManualSelection ? excerptEnd - excerptStart >= 1 : !selectedIDs.isEmpty)
  }

  private var creationTitle: String {
    let count = usesManualSelection ? 1 : selectedIDs.count
    return count > 1 ? "Create \(count) practices" : "Create practice"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text(model.mimicDraft == nil ? "New reference practice" : "Choose phrases")
          .font(.title2.weight(.semibold))
        Text(model.mimicDraft == nil
          ? "Import a clip or capture audio playing on your Mac."
          : usesManualSelection ? "Choose a clip to create a practice."
          : "Select phrases to create a practice for each.")
          .font(.callout)
          .foregroundStyle(Studio.secondary)
      }

      if let draft = model.mimicDraft {
        HStack {
          Text(draft.sourceName).font(.callout).foregroundStyle(Studio.secondary).lineLimit(1)
          Spacer()
          Button("Change audio", action: model.cancelMimicPreparation)
            .disabled(model.mimicIsPreparing)
        }
        if usesManualSelection {
          ManualPracticeExcerptView(
            draft: draft, start: $excerptStart, end: $excerptEnd)
            .disabled(model.mimicIsPreparing)
        } else {
          PracticePhrasePicker(
            draft: draft, clips: model.suggestedPracticeClips, selectedIDs: $selectedIDs)
            .disabled(model.mimicIsPreparing)
        }
      } else {
        MimicReferencePicker()
      }

      HStack(spacing: 12) {
        if let progress = model.practiceClipCreationProgress {
          ProgressView().controlSize(.small)
          Text("Creating \(progress.completed) of \(progress.total)…")
            .font(.callout).foregroundStyle(Studio.secondary)
        } else if model.mimicDraft != nil, !model.suggestedPracticeClips.isEmpty {
          Button(chooseManually ? "Suggested phrases" : "Choose a clip manually") {
            model.stopPlayback()
            chooseManually.toggle()
          }
        }
        Spacer()
        Button("Cancel") {
          model.cancelMimicPreparation()
          model.navigate(to: .home)
        }
        .keyboardShortcut(.cancelAction)
        .studioGlassButton()
        Button(creationTitle) {
          guard let draft = model.mimicDraft else { return }
          if usesManualSelection {
            model.createManualPracticeSession(draftID: draft.id, start: excerptStart, end: excerptEnd)
          } else {
            model.createSuggestedPracticeSessions(draftID: draft.id, clipIDs: selectedIDs)
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canCreate)
        .studioGlassButton(prominent: canCreate)
      }
    }
    .padding(24)
    .onChange(of: model.mimicDraft?.id, initial: true) { _, _ in
      selectedIDs = []
      chooseManually = false
      excerptStart = 0
      excerptEnd = min(model.mimicDraft?.duration ?? 0, 20)
    }
    .onDisappear { model.cancelMimicPreparation() }
  }
}

private struct PracticePhrasePicker: View {
  let draft: MimicReferenceDraft
  let clips: [SuggestedPracticeClip]
  @Binding var selectedIDs: Set<Int>
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot

  var body: some View {
    Group {
      if snapshot {
        VStack(spacing: 0) { rows }
      } else {
        ScrollView {
          VStack(spacing: 0) { rows }
        }
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: min(300, CGFloat(clips.count) * 76), alignment: .top)
    .clipped()
    .padding(.horizontal, 14)
    .desktopPanel()
    .accessibilityLabel("Phrases to practise")
  }

  private var rows: some View {
    ForEach(clips) { clip in
      HStack(spacing: 12) {
        if snapshot {
          Image(systemName: "square").foregroundStyle(Studio.secondary)
          phraseLabel(clip)
          Image(systemName: "play.fill").foregroundStyle(Studio.accent)
        } else {
          Toggle(isOn: Binding(
            get: { selectedIDs.contains(clip.id) },
            set: { selected in
              if selected { selectedIDs.insert(clip.id) } else { selectedIDs.remove(clip.id) }
            }
          )) { phraseLabel(clip) }
          .toggleStyle(.checkbox)
          let playing = model.isPlaying && model.practiceClipPreviewID == clip.id
          Button {
            model.previewSuggestedPracticeClip(draftID: draft.id, clipID: clip.id)
          } label: {
            Image(systemName: playing ? "stop.fill" : "play.fill").frame(width: 28, height: 28)
          }
          .buttonStyle(.borderless)
          .accessibilityLabel(playing ? "Stop phrase" : "Play: \(clip.text)")
        }
      }
      .frame(minHeight: 76)
      if clip.id != clips.last?.id { Divider() }
    }
  }

  private func phraseLabel(_ clip: SuggestedPracticeClip) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(clip.text).font(.callout).lineLimit(2).help(clip.text)
      Text("\(vcNumber(clip.duration, 1))s")
        .font(.caption.monospacedDigit()).foregroundStyle(Studio.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
