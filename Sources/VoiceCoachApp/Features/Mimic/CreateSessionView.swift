import SwiftUI
import VoiceCoachSession

struct CreateSessionView: View {
  @EnvironmentObject private var model: AppModel
  @State private var excerptStart = 0.0
  @State private var excerptEnd = 0.0

  init(initialMode: PracticeMode = .mimic) {}

  private var canStart: Bool {
    model.mimicDraft != nil
      && !model.mimicIsPreparing
      && !model.isCapturingMimicReference
      && (excerptEnd - excerptStart >= 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("New Mimic")
            .font(.title2.weight(.semibold))
          Spacer()
        }

        Text("Import a clip or capture Mac audio.")
          .font(.callout)
          .foregroundStyle(Studio.secondary)
      }

      MimicReferencePicker(start: $excerptStart, end: $excerptEnd)

      if model.mimicDraft != nil || model.isCapturingMimicReference {
        Spacer(minLength: 0)
      }

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
        .disabled(!canStart)
        .studioGlassButton(prominent: canStart)
      }
    }
    .padding(24)
    .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
    .onChange(of: model.mimicDraft?.id) { _, _ in
      loadMimicDraft()
    }
    .onAppear { if excerptEnd == 0 { loadMimicDraft() } }
    .onDisappear { model.cancelMimicPreparation() }
  }

  private func loadMimicDraft() {
    guard let draft = model.mimicDraft else { return }
    excerptStart = 0
    excerptEnd = min(draft.duration, 20)
  }
}
