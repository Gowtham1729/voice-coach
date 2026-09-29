import SwiftUI

@main
struct VoiceCoachApplication: App {
  @StateObject private var model = AppModel()
  @StateObject private var updater = AppUpdater()

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
      VoiceCoachCommands(model: model, updater: updater)
    }

    Settings {
      SettingsView()
        .environmentObject(model)
    }
  }
}
