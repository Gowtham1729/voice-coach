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
      guard selection.isValid(in: draft.duration) else { return nil }
      if let id = selection.phraseID {
        guard let clip = clips.first(where: { $0.id == id }) else { return nil }
        let unchanged = selection.start == clip.start && selection.end == clip.end
        excerpts.append(
          PracticeExcerpt(
            start: selection.start, end: selection.end,
            name: String(clip.text.prefix(80)),
            transcription: unchanged ? clip.transcription : nil))
      } else {
        excerpts.append(
          PracticeExcerpt(
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
    let locale =
      draft.transcriptionLocaleIdentifier.map(Locale.init(identifier:))
      ?? newSessionTranscriptionLocale

    let task = Task {
      var stagedIDs: [UUID] = []
      var committed = false
      var currentPhrase: String?
      var firstNotice: String?
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
          currentPhrase = excerpt.name
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
            transcription = outcome.transcription
            try Task.checkCancellation()
            if firstNotice == nil { firstNotice = outcome.notice }
          }
          try Task.checkCancellation()
          let reference = PracticeSession(
            audioURL: url, source: draft.source, result: acoustic,
            transcription: transcription,
            words: transcription.map {
              WordAcousticAnalyzer().analyze(transcription: $0, result: acoustic)
            } ?? [])
          let name = excerpt.name ?? draft.sourceName
          prepared.append(
            CoachingSession(
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
        // One base time with strictly decreasing offsets keeps the first phrase first,
        // both now and after a reload sorted by `updatedAt`.
        let base = Date()
        for index in prepared.indices {
          prepared[index].updatedAt = base.addingTimeInterval(-Double(index) / 1000)
        }
        let previousSessions = sessions
        sessions.insert(contentsOf: prepared, at: 0)
        guard persist(analysisTakeIDs: Set(prepared.compactMap { $0.mimicReference?.take.id }))
        else {
          sessions = previousSessions
          return
        }
        committed = true
        transcriptionNotice = firstNotice
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
        toastMessage =
          prepared.count == 1
          ? "Practice created" : "\(prepared.count) practices created"
      } catch is CancellationError {
        // A cancelled or dismissed creation never publishes staged references.
      } catch {
        if !Task.isCancelled, mimicPreparationID == draftID {
          presentError(
            title: "Practices weren’t created",
            message: Self.practiceCreationFailureMessage(error, phrase: currentPhrase))
        }
      }
    }
    practiceClipCreationTask = task
    return task
  }

  /// Names the phrase when one clip has no audio or no recognized speech.
  static func practiceCreationFailureMessage(_ error: Error, phrase: String?) -> String {
    let fallback = "Couldn’t prepare the selected phrases. Try again."
    guard let phrase else { return userFacingMessage(error, fallback: fallback) }
    let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
    let label = trimmed.count > 40 ? "\(trimmed.prefix(40))…" : trimmed
    switch error {
    case AnalysisError.silentRecording, AnalysisError.emptyRecording:
      return "No audio detected in ‘\(label)’. Deselect it or adjust its edges, then try again."
    case TranscriptionError.noSpeechRecognized:
      return "No speech recognized in ‘\(label)’. Deselect it or adjust its edges, then try again."
    default:
      return userFacingMessage(error, fallback: fallback)
    }
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
