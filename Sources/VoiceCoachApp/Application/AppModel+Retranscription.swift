import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  @discardableResult
  func retranscribeMimicReference() -> Task<Void, Never>? {
    guard let session = selectedSession, let reference = session.mimicReference else { return nil }
    return retranscribe(reference.take, sessionID: session.id, isReference: true)
  }

  @discardableResult
  func retranscribeSelectedTake() -> Task<Void, Never>? {
    guard let session = selectedSession, let take = selectedTake else { return nil }
    return retranscribe(take, sessionID: session.id, isReference: false)
  }

  var canRetranscribe: Bool {
    !isRecording && !isAnalyzing && !mimicIsPreparing && !isCapturingMimicReference
      && mimicPhase == .ready
  }

  private func retranscribe(
    _ take: PracticeSession, sessionID: UUID, isReference: Bool
  ) -> Task<Void, Never>? {
    guard canRetranscribe else { return nil }
    let engine = transcriptionEngine
    let locale = retranscriptionLocale(engine: engine)
    stopPlayback()
    isAnalyzing = true
    transcriptionNotice = nil
    return Task {
      defer { isAnalyzing = false }
      do {
        let outcome = try await transcribe(take.audioURL, engine, locale)
        try RecordingValidation.validateTranscription(outcome.result)
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

  /// Apple uses the Settings language. Parakeet stays automatic and only receives a saved
  /// session language so an unsupported language can be rejected before the model runs.
  private func retranscriptionLocale(engine: TranscriptionEnginePreference) -> Locale? {
    switch engine {
    case .system:
      transcriptionLocale
    case .parakeet:
      selectedSession?.transcriptionLocaleIdentifier.map(Locale.init(identifier:))
    }
  }
}
