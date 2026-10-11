import SwiftUI

struct CreateSessionView: View {
  @EnvironmentObject private var model: AppModel
  @State private var editor = PracticeClipEditor()

  private var canCreate: Bool {
    model.mimicDraft != nil && !model.mimicIsPreparing && !model.isCapturingMimicReference
      && !editor.creationSelections.isEmpty
      && editor.creationSelections.allSatisfy { $0.end - $0.start >= 1 }
  }

  private var creationTitle: String {
    let count = editor.creationSelections.count
    return count > 1 ? "Create \(count) practices" : "Create practice"
  }

  private var title: String {
    if model.mimicDraft == nil { return "New reference practice" }
    return editor.clips.isEmpty ? "Choose a clip" : "Choose phrases"
  }

  private var instruction: String {
    if model.mimicDraft == nil { return "Import a clip or capture audio playing on your Mac." }
    if editor.clips.isEmpty { return "Drag the handles to choose the clip you want to practise." }
    return "Choose a phrase, then adjust its edges if needed."
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.title2.weight(.semibold))
        Text(instruction)
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
        PracticeAudioSelector(draft: draft, editor: $editor)
          .disabled(model.mimicIsPreparing)
      } else {
        MimicReferencePicker()
      }

      HStack(spacing: 12) {
        if let progress = model.practiceClipCreationProgress {
          ProgressView().controlSize(.small)
          Text("Creating \(progress.completed) of \(progress.total)…")
            .font(.callout).foregroundStyle(Studio.secondary)
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
          model.createPracticeSessions(draftID: draft.id, selections: editor.creationSelections)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canCreate)
        .studioGlassButton(prominent: canCreate)
      }
    }
    .padding(24)
    .onChange(of: model.mimicDraft?.id, initial: true) { _, _ in
      editor = PracticeClipEditor(
        clips: model.suggestedPracticeClips, duration: model.mimicDraft?.duration ?? 0)
    }
    .onDisappear { model.cancelMimicPreparation() }
  }
}
