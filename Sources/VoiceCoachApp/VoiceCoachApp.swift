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
                .frame(minWidth: 1080, minHeight: 700)
                #if DEBUG
                .background(PreviewRenderLauncher())
                #endif
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1280, height: 820)
    }
}
