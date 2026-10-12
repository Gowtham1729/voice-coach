import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  /// QA entry point that deliberately uses the same import preparation and
  /// analysis/save path as a take imported through the app.
  func injectTakeFromEnvironment() {
    guard let path = ProcessInfo.processInfo.environment["VOICECOACH_INJECT_TAKE"],
      !path.isEmpty, let session = selectedSession,
      !isRecording, !isAnalyzing
    else { return }

    let sourceURL = URL(fileURLWithPath: path)
    guard sourceURL.pathExtension.lowercased() == "wav" else {
      presentError(title: "QA import failed", message: "VOICECOACH_INJECT_TAKE needs a WAV file.")
      return
    }
    let takeID = UUID()
    do {
      let destinationURL = try store.importedAudioURL(
        sessionID: session.id, takeID: takeID, fileExtension: "wav")
      isAnalyzing = true
      clearError()
      Task {
        do {
          try await AudioImportService.prepareAudio(from: sourceURL, to: destinationURL)
          analyze(url: destinationURL, takeID: takeID, source: .importedAudio)
        } catch {
          try? FileManager.default.removeItem(at: destinationURL)
          isAnalyzing = false
          presentError(
            title: "QA import failed", error: error,
            fallback: "Couldn’t prepare the WAV file.")
        }
      }
    } catch {
      presentError(
        title: "QA import failed", error: error,
        fallback: "Couldn’t create a take file.")
    }
  }
}
