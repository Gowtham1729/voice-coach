import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  func suggestedPracticeClips(for take: PracticeSession) -> [SuggestedPracticeClip] {
    PracticeClipSuggestions.clips(
      transcription: take.transcription, duration: take.result.metrics.duration)
  }

  func previewSuggestedPracticeClip(takeID: UUID, clipID: Int) {
    guard !isRecording, !isAnalyzing, !mimicIsPreparing, !isCapturingMimicReference,
      let take = selectedTake, take.id == takeID,
      let clip = suggestedPracticeClips(for: take).first(where: { $0.id == clipID })
    else { return }
    let shouldStop = isPlaying && practiceClipPreviewID == clipID
    stopPlayback()
    guard !shouldStop else { return }
    do {
      recorder.playbackVolume = 1
      try recorder.play(url: take.audioURL, from: clip.start)
      playbackTime = clip.start
      mimicPlaybackEnd = clip.end
      practiceClipPreviewID = clipID
      isPlaying = true
      startPlaybackTimer()
    } catch {
      presentError(title: "Playback failed", message: "This clip couldn’t be played.")
    }
  }

  /// Stage the entire batch before publishing it to the library. Failure or
  /// cancellation removes every new folder and leaves the source recording intact.
  @discardableResult
  func createSuggestedPracticeSessions(takeID: UUID, clipIDs: Set<Int>) -> Task<Void, Never>? {
    guard !isRecording, !isAnalyzing, !isRequestingPermission,
      !mimicIsPreparing, !isCapturingMimicReference,
      let take = selectedTake, take.id == takeID,
      let sourceSession = selectedSession, !sourceSession.isMimic
    else { return nil }
    let clips = suggestedPracticeClips(for: take).filter { clipIDs.contains($0.id) }
    guard !clips.isEmpty, clips.count == clipIDs.count else { return nil }
    stopPlayback()
    clearError()
    toastMessage = nil
    isAnalyzing = true
    practiceClipCreationProgress = (0, clips.count)

    let task = Task {
      var stagedIDs: [UUID] = []
      var committed = false
      defer {
        if !committed {
          for id in stagedIDs { try? store.deleteSessionData(sessionID: id) }
        }
        isAnalyzing = false
        practiceClipCreationProgress = nil
        practiceClipCreationTask = nil
      }
      do {
        var prepared: [CoachingSession] = []
        for clip in clips {
          try Task.checkCancellation()
          let sessionID = UUID()
          stagedIDs.append(sessionID)
          let url = try store.referenceURL(sessionID: sessionID)
          let acoustic = try await preparePracticeClip(take.audioURL, url, clip.start, clip.end)
          try Task.checkCancellation()
          try RecordingValidation.validateAudio(acoustic)
          let reference = PracticeSession(
            audioURL: url, source: take.takeSource, result: acoustic,
            transcription: clip.transcription,
            words: WordAcousticAnalyzer().analyze(transcription: clip.transcription, result: acoustic))
          let name = String(clip.text.prefix(80))
          prepared.append(CoachingSession(
            id: sessionID, name: name, mode: .mimic, prompt: "", keepsRecordings: true,
            mimicReference: MimicReference(
              sourceName: name, take: reference,
              sourceStart: clip.start, sourceEnd: clip.end),
            mimicStyle: .listenAndRepeat, mimicAttemptStyles: [:],
            transcriptionLocaleIdentifier:
              clip.transcription.localeIdentifier ?? sourceSession.transcriptionLocaleIdentifier))
          practiceClipCreationProgress = (prepared.count, clips.count)
        }
        try Task.checkCancellation()
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
        toastMessage = prepared.count == 1
          ? "Practice session created" : "\(prepared.count) practice sessions created"
      } catch is CancellationError {
        // Selection remains available so the user can change it and try again.
      } catch {
        presentError(
          title: "Practice sessions weren’t created", error: error,
          fallback: "Couldn’t prepare the selected clips. Try again; your recording is still saved.")
      }
    }
    practiceClipCreationTask = task
    return task
  }

  func cancelSuggestedPracticeCreation() {
    practiceClipCreationTask?.cancel()
  }
}
