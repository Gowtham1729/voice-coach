import SwiftUI

@main
struct VoiceCoachApplication: App {
  @NSApplicationDelegateAdaptor(VoiceCoachApplicationDelegate.self) private var appDelegate
  @StateObject private var model = Self.makeModel()
  @StateObject private var updater = AppUpdater()
  @AppStorage("voiceCoach.showMenuBarExtra") private var showsMenuBarExtra = true

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

  private static func makeModel() -> AppModel {
    #if DEBUG
      if let index = CommandLine.arguments.firstIndex(of: "--test-library"),
        CommandLine.arguments.indices.contains(index + 1)
      {
        let model = AppModel(storageRoot: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        LiveCaptureSmoke.runIfRequested(model: model)
        return model
      }
    #endif
    return AppModel()
  }

  var body: some Scene {
    WindowGroup("Ichido", id: IchidoMainWindow.sceneID) {
      SystemAppearanceRoot {
        ContentView()
          .environmentObject(model)
          .frame(minWidth: 920, minHeight: 640)
          .background(IchidoMainWindowMarker())
          .onAppear { appDelegate.model = model }
          #if DEBUG
            .background(PreviewRenderLauncher())
          #endif
      }
    }
    .defaultSize(width: 1240, height: 800)
    .commands {
      VoiceCoachCommands(model: model, updater: updater)
    }

    MenuBarExtra(isInserted: menuBarVisibility) {
      SystemAppearanceRoot {
        QuickPracticeMenu(model: model)
          .onAppear { appDelegate.model = model }
      }
    } label: {
      IchidoMenuBarLabel(model: model)
    }
    .menuBarExtraStyle(.window)

    Settings {
      SystemAppearanceRoot {
        SettingsView()
          .environmentObject(model)
      }
    }
  }

  private var menuBarVisibility: Binding<Bool> {
    Binding(
      get: { showsMenuBarExtra },
      set: { isInserted in
        // MenuBarExtra reports its current insertion state during scene updates.
        // Rewriting the same AppStorage value causes a scene-update loop on macOS 27.
        if showsMenuBarExtra != isInserted { showsMenuBarExtra = isInserted }
      }
    )
  }
}
