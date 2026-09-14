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
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 800, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 840)
    }
}
