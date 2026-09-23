import SwiftUI
import VoiceCoachSession

struct VoiceCoachCommands: Commands {
  @ObservedObject var model: AppModel

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("Record") { model.startHomeRecording() }
        .keyboardShortcut("n", modifiers: .command)
        .disabled(model.isRecording || model.isAnalyzing || model.isRequestingPermission)

      Button("Mimic…") { model.startMimic() }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .disabled(model.isRecording || model.isAnalyzing || model.isRequestingPermission)
    }

    CommandGroup(after: .importExport) {
      Button("Import…") { model.importClip() }
        .keyboardShortcut("i", modifiers: [.command, .shift])
        .disabled(
          model.isRecording || model.isAnalyzing || model.isRequestingPermission
            || (model.selectedSession?.mode == .mimic && model.destination.isWorkspace))

      Button("Export…") { model.exportCurrent() }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .disabled(model.selectedTake == nil || model.isRecording || model.isAnalyzing)

      Button("Copy AI analysis prompt + JSON") { model.copySelectedAIAnalysisPrompt() }
        .keyboardShortcut("c", modifiers: [.command, .option])
        .disabled(model.selectedTake == nil || model.isRecording || model.isAnalyzing)
    }

    CommandMenu("Navigate") {
      navigationButton("Home", section: .home, shortcut: "1")
      navigationButton("Library", section: .library, shortcut: "2")
      navigationButton("Mimics", section: .mimics, shortcut: "3")
    }

    CommandMenu("Practice") {
      Button(
        model.mimicPhase == .playingReference
          ? "Stop"
          : model.isPlaying ? "Pause" : "Play"
      ) {
        model.toggleMimicPlayback()
      }
      .disabled(
        !model.isMimicWorkspace || model.isRecording || model.isAnalyzing
          || (model.mimicPhase != .ready && model.mimicPhase != .playingReference))

      Button(model.isRecording ? "Stop Recording" : "Practice") {
        model.recordButtonPressed()
      }
      .keyboardShortcut("r", modifiers: .command)
      .disabled(
        !model.isMimicWorkspace || model.isAnalyzing || model.isRequestingPermission
          || (!model.isRecording && (model.isPlaying || model.mimicPhase != .ready)))
    }
  }

  private func navigationButton(
    _ title: String, section: NavigationSection, shortcut: KeyEquivalent
  ) -> some View {
    Button(title) { model.navigate(toSection: section) }
      .keyboardShortcut(shortcut, modifiers: .command)
      .disabled(model.isRecording)
  }
}
