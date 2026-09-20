import SwiftUI

@main
struct VoiceCoachApplication: App {
    @StateObject private var model = AppModel()

    init() {
        #if DEBUG
        renderStudioPreviewsIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup("Voice Coach") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 640)
                #if DEBUG
                .background(PreviewRenderLauncher())
                #endif
        }
        .defaultSize(width: 1240, height: 800)
        .commands {
            VoiceCoachCommands(model: model)
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

private struct VoiceCoachCommands: Commands {
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
            Button("Import Recording…") { model.importClip() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(model.isRecording || model.isAnalyzing || model.isRequestingPermission || (model.selectedSession?.mode == .mimic && model.destination.isWorkspace))

            Button("Export Current Recording…") { model.exportCurrent() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.selectedTake == nil || model.isRecording || model.isAnalyzing)
        }

        CommandMenu("Navigate") {
            navigationButton("Home", section: .home, shortcut: "1")
            navigationButton("Library", section: .library, shortcut: "2")
            navigationButton("Mimics", section: .mimics, shortcut: "3")
        }

        CommandMenu("Practice") {
            Button(model.mimicPhase == .playingReference ? "Cancel Reference Playback" :
                   model.isPlaying ? "Pause Mimic Playback" : "Play Mimic Audio") {
                model.toggleMimicPlayback()
            }
            .disabled(!model.isMimicWorkspace || model.isRecording || model.isAnalyzing ||
                      (model.mimicPhase != .ready && model.mimicPhase != .playingReference))

            Button(model.isRecording ? "Stop Mimic Recording" : "Start Mimic Practice") {
                model.recordButtonPressed()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!model.isMimicWorkspace || model.isAnalyzing || model.isRequestingPermission ||
                      (!model.isRecording && (model.isPlaying || model.mimicPhase != .ready)))
        }
    }

    private func navigationButton(_ title: String, section: NavigationSection, shortcut: KeyEquivalent) -> some View {
        Button(title) { model.navigate(toSection: section) }
            .keyboardShortcut(shortcut, modifiers: .command)
            .disabled(model.isRecording)
    }
}
