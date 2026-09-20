import Foundation
import VoiceCoachSession

/// Live service graph for the app coordinator. Protocol-backed edges keep platform
/// services replaceable without leaking them into SwiftUI views.
@MainActor
struct AppDependencies {
  let recorder: any AudioRecording
  let systemAudioCapture: any SystemAudioCapturing
  let sessionStore: any SessionStoring

  static func live(storageRoot: URL? = nil) throws -> AppDependencies {
    AppDependencies(
      recorder: AudioRecorder(),
      systemAudioCapture: SystemAudioCapture(),
      sessionStore: try SessionStore(rootURL: storageRoot)
    )
  }
}
