import SwiftUI
import VoiceCoachSession

struct CreateSessionView: View {
  @EnvironmentObject private var model: AppModel
  @State private var excerptStart = 0.0
  @State private var excerptEnd = 0.0

  init(initialMode: PracticeMode = .mimic) {}

  var body: some View {
    StudioPage(maxWidth: 760, horizontalPadding: 24) {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Text("New Mimic")
            .font(.title2.weight(.semibold))
          Spacer()
        }

        Text("Import a clip or capture Mac audio, then trim a short excerpt.")
          .font(.callout)
          .foregroundStyle(Studio.secondary)

        MimicReferencePicker(start: $excerptStart, end: $excerptEnd)

        HStack {
          Spacer()
          Button("Cancel") {
            model.cancelMimicPreparation()
            model.navigate(to: .home)
          }
          .tint(.primary)
          .keyboardShortcut(.cancelAction)
          .studioGlassButton()
          Button("Start") {
            let name = model.mimicDraft?.sourceName ?? "Mimic"
            model.createMimicSession(name: name, start: excerptStart, end: excerptEnd)
          }
          .keyboardShortcut(.defaultAction)
          .disabled(
            model.mimicDraft == nil || model.mimicIsPreparing || model.isCapturingMimicReference
              || excerptEnd - excerptStart < 1
          )
          .studioGlassButton(prominent: true)
        }
      }
      .onChange(of: model.mimicDraft?.id) { _, _ in
        loadMimicDraft()
      }
      .onAppear { if excerptEnd == 0 { loadMimicDraft() } }
      .onDisappear { model.cancelMimicPreparation() }
    }
  }

  private func loadMimicDraft() {
    guard let draft = model.mimicDraft else { return }
    excerptStart = 0
    excerptEnd = min(draft.duration, 20)
  }
}
