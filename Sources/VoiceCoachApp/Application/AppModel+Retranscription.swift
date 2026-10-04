import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  func retranscribeMimicReference() {
    guard let session = selectedSession, let reference = session.mimicReference else { return }
    retranscribe(reference.take, sessionID: session.id, isReference: true)
  }

  func retranscribeSelectedTake() {
    guard let session = selectedSession, let take = selectedTake else { return }
    retranscribe(take, sessionID: session.id, isReference: false)
  }

  private func retranscribe(_ take: PracticeSession, sessionID: UUID, isReference: Bool) {
    guard !isRecording, !isAnalyzing, !mimicIsPreparing, !isCapturingMimicReference,
      mimicPhase == .ready
    else { return }
    let engine = transcriptionEngine
    let locale =
      engine == .system
      ? transcriptionLocale
      : selectedSession?.transcriptionLocaleIdentifier.map(Locale.init(identifier:))
    stopPlayback()
    isAnalyzing = true
    transcriptionNotice = nil
    Task {
      defer { isAnalyzing = false }
      do {
        let outcome = try await TranscriptionService(preferredEngine: engine, locale: locale)
          .transcribe(url: take.audioURL)
        let updatedTake = PracticeSession(
          id: take.id, createdAt: take.createdAt, audioURL: take.audioURL, source: take.source,
          result: take.result, transcription: outcome.result,
          words: WordAcousticAnalyzer().analyze(transcription: outcome.result, result: take.result)
        )
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let previousSessions = sessions
        if isReference {
          guard sessions[index].mimicReference?.take.id == take.id else { return }
          sessions[index].mimicReference?.take = updatedTake
        } else {
          guard let takeIndex = sessions[index].takes.firstIndex(where: { $0.id == take.id }) else {
            return
          }
          sessions[index].takes[takeIndex] = updatedTake
        }
        if let locale { sessions[index].transcriptionLocaleIdentifier = locale.identifier }
        guard persist(analysisTakeIDs: [take.id]) else {
          sessions = previousSessions
          return
        }
        transcriptionNotice = outcome.notice
        if reportCache?.takeID == take.id { reportCache = nil }
        toastMessage = "Transcript updated"
        mimicSelectedWord = nil
      } catch {
        presentError(
          title: "Transcript couldn’t be updated", error: error,
          fallback: "Transcription failed. Your existing audio and transcript were kept.")
      }
    }
  }
}
