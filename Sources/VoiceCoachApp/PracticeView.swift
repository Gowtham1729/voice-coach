import SwiftUI

/// Practice and Studio share one focused workspace. Route identity remains
/// intact so recording and playback lifecycles continue to use AppModel.
struct PracticeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.selectedSession?.mode == .mimic {
            MimicWorkspace()
        } else {
            DesktopStudioWorkspace()
        }
    }
}
