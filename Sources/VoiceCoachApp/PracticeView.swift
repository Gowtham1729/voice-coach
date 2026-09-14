import SwiftUI

/// Practice and Studio share one focused workspace. Route identity remains
/// intact so recording and playback lifecycles continue to use AppModel.
struct PracticeView: View {
    var body: some View {
        DesktopStudioWorkspace()
    }
}
