import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  var suggestedPracticeClips: [SuggestedPracticeClip] {
    guard let draft = mimicDraft else { return [] }
    return PracticeClipSuggestions.clips(
      transcription: draft.transcription, duration: draft.duration)
  }

  @discardableResult
  func createSuggestedPracticeSessions(draftID: UUID, clipIDs: Set<Int>) -> Task<Void, Never>? {
    let clips = suggestedPracticeClips.filter { clipIDs.contains($0.id) }
    guard !clips.isEmpty, clips.count == clipIDs.count else { return nil }
    return createPracticeSessions(draftID: draftID, selections: clips.map {
      PracticeClipSelection(phraseID: $0.id, start: $0.start, end: $0.end)
    })
  }

  @discardableResult
  func createManualPracticeSession(draftID: UUID, start: Double, end: Double) -> Task<Void, Never>? {
    createPracticeSessions(draftID: draftID, selections: [
      PracticeClipSelection(phraseID: nil, start: start, end: end)
    ])
  }

  @discardableResult
  func createPracticeSessions(
    draftID: UUID, selections: [PracticeClipSelection]
  ) -> Task<Void, Never>? {
    guard let draft = mimicDraft, draft.id == draftID, !selections.isEmpty,
      Set(selections.map(\.phraseID)).count == selections.count,
      selections.count == 1 || selections.allSatisfy({ $0.phraseID != nil })
    else { return nil }
    let clips = suggestedPracticeClips
    var excerpts: [PracticeExcerpt] = []
    for selection in selections {
      guard selection.start.isFinite, selection.end.isFinite, selection.start >= 0,
        selection.end <= draft.duration, selection.end - selection.start >= 1
      else { return nil }
      if let id = selection.phraseID {
        guard let clip = clips.first(where: { $0.id == id }) else { return nil }
        let unchanged = selection.start == clip.start && selection.end == clip.end
        excerpts.append(PracticeExcerpt(
          start: selection.start, end: selection.end,
          name: String(clip.text.prefix(80)),
          transcription: unchanged ? clip.transcription : nil))
      } else {
        excerpts.append(PracticeExcerpt(
          start: selection.start, end: selection.end, name: nil, transcription: nil))
      }
    }
    return createPracticeReferences(draftID: draftID, excerpts: excerpts)
  }

  private func createPracticeReferences(
    draftID: UUID, excerpts: [PracticeExcerpt]
  ) -> Task<Void, Never>? {
    guard !isRecording, !isAnalyzing, !isRequestingPermission, !mimicIsPreparing,
      !isCapturingMimicReference, mimicPreparationID == draftID,
      let draft = mimicDraft, draft.id == draftID
    else { return nil }
    stopPlayback()
    clearError()
    toastMessage = nil
    transcriptionNotice = nil
    isAnalyzing = true
    mimicIsPreparing = true
    let batchID = UUID()
    practiceClipCreationID = batchID
    practiceClipCreationProgress = (0, excerpts.count)
    let engine = transcriptionEngine
    let locale = draft.transcriptionLocaleIdentifier.map(Locale.init(identifier:))
      ?? newSessionTranscriptionLocale

    let task = Task {
      var stagedIDs: [UUID] = []
      var committed = false
      defer {
        if !committed {
          for id in stagedIDs { try? store.deleteSessionData(sessionID: id) }
        }
        if practiceClipCreationID == batchID {
          isAnalyzing = false
          mimicIsPreparing = false
          practiceClipCreationProgress = nil
          practiceClipCreationTask = nil
          practiceClipCreationID = nil
        }
      }
      do {
        var prepared: [CoachingSession] = []
        for excerpt in excerpts {
          try Task.checkCancellation()
          let sessionID = UUID()
          stagedIDs.append(sessionID)
          let url = try store.referenceURL(sessionID: sessionID)
          let acoustic = try await preparePracticeClip(
            draft.url, url, excerpt.start, excerpt.end)
          try Task.checkCancellation()
          try RecordingValidation.validateAudio(acoustic)
          var transcription = excerpt.transcription
          if transcription == nil {
            let outcome = try await transcribeForAnalysis(url: url, engine: engine, locale: locale)
            transcription = outcome.0
            transcriptionNotice = outcome.1
          }
          try Task.checkCancellation()
          let reference = PracticeSession(
            audioURL: url, source: draft.source, result: acoustic,
            transcription: transcription,
            words: transcription.map {
              WordAcousticAnalyzer().analyze(transcription: $0, result: acoustic)
            } ?? [])
          let name = excerpt.name ?? draft.sourceName
          prepared.append(CoachingSession(
            id: sessionID, name: name, mode: .mimic, prompt: "", keepsRecordings: true,
            mimicReference: MimicReference(
              sourceName: name, take: reference,
              sourceStart: excerpt.start, sourceEnd: excerpt.end),
            mimicStyle: .listenAndRepeat, mimicAttemptStyles: [:],
            transcriptionLocaleIdentifier: transcription?.localeIdentifier ?? locale?.identifier))
          practiceClipCreationProgress = (prepared.count, excerpts.count)
        }
        try Task.checkCancellation()
        guard mimicPreparationID == draftID else { throw CancellationError() }
        let previousSessions = sessions
        sessions.insert(contentsOf: prepared, at: 0)
        guard persist(analysisTakeIDs: Set(prepared.compactMap { $0.mimicReference?.take.id })) else {
          sessions = previousSessions
          return
        }
        committed = true
        lastUsedMimicID = prepared.first?.id
        if let only = prepared.first, prepared.count == 1 {
          selectedSessionID = only.id
          selectedTakeID = nil
          mimicWorkspaceMode = .practice
          destination = .practice(only.id)
        } else {
          selectedSessionID = nil
          selectedTakeID = nil
          destination = .mimics
        }
        cancelMimicPreparation()
        toastMessage = prepared.count == 1
          ? "Practice created" : "\(prepared.count) practices created"
      } catch is CancellationError {
        // A cancelled or dismissed creation never publishes staged references.
      } catch {
        if !Task.isCancelled, mimicPreparationID == draftID {
          presentError(
            title: "Practices weren’t created", error: error,
            fallback: "Couldn’t prepare the selected phrases. Try again.")
        }
      }
    }
    practiceClipCreationTask = task
    return task
  }

  func cancelSuggestedPracticeCreation() {
    practiceClipCreationTask?.cancel()
    practiceClipCreationTask = nil
    practiceClipCreationID = nil
    if practiceClipCreationProgress != nil {
      practiceClipCreationProgress = nil
      isAnalyzing = false
      mimicIsPreparing = false
    }
  }
}

private struct PracticeExcerpt {
  let start: Double
  let end: Double
  let name: String?
  let transcription: TranscriptionResult?
}
