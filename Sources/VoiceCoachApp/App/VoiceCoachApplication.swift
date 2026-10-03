import SwiftUI

@main
struct VoiceCoachApplication: App {
  @StateObject private var model = AppModel()
  @StateObject private var updater = AppUpdater()

  init() {
    #if DEBUG
      renderStudioPreviewsIfRequested()
    #endif
    // Clear this before AppKit latches appearance. A saved YES value forces
    // Aqua for the life of the process and ignores System Settings.
    if !CommandLine.arguments.contains("--render-previews") {
      UserDefaults.standard.removeObject(forKey: "NSRequiresAquaSystemAppearance")
    }
  }

  var body: some Scene {
    WindowGroup("Voice Coach") {
      SystemAppearanceRoot {
        ContentView()
          .environmentObject(model)
          .frame(minWidth: 920, minHeight: 640)
          #if DEBUG
            .background(PreviewRenderLauncher())
          #endif
      }
    }
    .defaultSize(width: 1240, height: 800)
    .commands {
      VoiceCoachCommands(model: model, updater: updater)
    }

    Settings {
      SystemAppearanceRoot {
        SettingsView()
          .environmentObject(model)
      }
    }
  }
}
