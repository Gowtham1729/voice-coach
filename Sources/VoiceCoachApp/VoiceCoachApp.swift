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
                .frame(minWidth: 980, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
    }
}
