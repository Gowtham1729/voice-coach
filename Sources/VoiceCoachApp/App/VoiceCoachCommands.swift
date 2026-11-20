import SwiftUI
import VoiceCoachSession

struct VoiceCoachCommands: Commands {
  @ObservedObject var model: AppModel
  let updater: AppUpdater

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Check for Updates…") { updater.checkForUpdates() }
    }

    CommandGroup(replacing: .newItem) {
      Button("New practice") { model.startHomeRecording() }
        .keyboardShortcut("n", modifiers: .command)
        .help("Start recording a new practice")
        .disabled(!model.canStartQuickPractice)

      Button("New practice with reference…") { model.startMimic() }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .disabled(!model.canStartQuickPractice)
    }

    CommandGroup(after: .importExport) {
      Button("Import…") { model.importClip() }
        .keyboardShortcut("i", modifiers: [.command, .shift])
        .disabled(
          model.isRecording || model.isAnalyzing || model.isRequestingPermission
            || model.isCapturingMimicReference || model.mimicIsPreparing || model.hasMenuBarReference
            || (model.selectedSession?.mode == .mimic && model.destination.isWorkspace))

      Button("Export take…") { model.exportCurrent() }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .disabled(model.selectedTake == nil || model.isRecording || model.isAnalyzing)

      if model.showsExperimentalAsk {
        Button("Copy AI analysis prompt + JSON") { model.copySelectedAIAnalysisPrompt() }
          .keyboardShortcut("c", modifiers: [.command, .option])
          .disabled(model.selectedTake == nil || model.isRecording || model.isAnalyzing)
      }
    }

    CommandMenu("Navigate") {
      listButton(.all, shortcut: "1")
      listButton(.withReference, shortcut: "2")
      listButton(.archived, shortcut: "3")
    }

    CommandMenu("Practice") {
      #if DEBUG
      if let path = ProcessInfo.processInfo.environment["VOICECOACH_INJECT_TAKE"], !path.isEmpty {
        Button("Inject QA take") { model.injectTakeFromEnvironment() }
          .keyboardShortcut("j", modifiers: [.command, .shift])
          .disabled(model.selectedSession == nil || model.isRecording || model.isAnalyzing)
      }
      #endif
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

      Button(model.isRecording ? "Stop recording" : "Record take") {
        model.recordButtonPressed()
      }
      .keyboardShortcut("r", modifiers: .command)
      .disabled(
        !model.isMimicWorkspace || model.isAnalyzing || model.isRequestingPermission
          || (!model.isRecording && (model.isPlaying || model.mimicPhase != .ready)))

      Divider()

      Button("Previous take") { model.stepTake(by: -1) }
        .keyboardShortcut(.leftArrow, modifiers: .option)
        .disabled(!model.destination.isWorkspace || !model.canStepTake(by: -1))

      Button("Next take") { model.stepTake(by: 1) }
        .keyboardShortcut(.rightArrow, modifiers: .option)
        .disabled(!model.destination.isWorkspace || !model.canStepTake(by: 1))

      if model.isMimicWorkspace, let style = model.selectedSession?.mimicStyle {
        Divider()
        Picker(
          "Mode",
          selection: Binding(
            get: { style },
            set: { model.updateMimicStyle($0) }
          )
        ) {
          ForEach(MimicStyle.allCases) { option in
            Text(option.title).tag(option)
          }
        }
        .pickerStyle(.inline)
        .disabled(model.isRecording || model.isAnalyzing || model.mimicPhase != .ready)
      }

      if model.showsExperimentalAsk {
        Button("Words") { model.revealSessionChat() }
          .keyboardShortcut("a", modifiers: [.command, .shift])
          .disabled(!model.destination.isWorkspace)
      }
    }
  }

  private func listButton(_ filter: PracticeListFilter, shortcut: KeyEquivalent) -> some View {
    Button(filter.title) { model.showList(filter) }
      .keyboardShortcut(shortcut, modifiers: .command)
      .disabled(!model.canNavigate)
  }
}
