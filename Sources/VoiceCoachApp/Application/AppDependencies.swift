import Foundation
import VoiceCoachCore
import VoiceCoachSession

/// Live service graph for the app coordinator. Protocol-backed edges keep platform
/// services replaceable without leaking them into SwiftUI views.
@MainActor
struct AppDependencies {
  let recorder: any AudioRecording
  let systemAudioCapture: any SystemAudioCapturing
  let sessionStore: any SessionStoring
  let sessionChatResponder: any SessionChatResponding
  var transcribe:
    @Sendable (URL, TranscriptionEnginePreference, Locale?) async throws -> TranscriptionOutcome = {
      url, engine, locale in
      try await TranscriptionService(preferredEngine: engine, locale: locale).transcribe(url: url)
    }

  static func live(storageRoot: URL? = nil) throws -> AppDependencies {
    AppDependencies(
      recorder: AudioRecorder(),
      systemAudioCapture: SystemAudioCapture(),
      sessionStore: try SessionStore(rootURL: storageRoot),
      sessionChatResponder: LocalSessionChatResponder()
    )
  }
}
