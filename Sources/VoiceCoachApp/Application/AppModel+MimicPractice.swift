import AVFoundation
import AppKit
import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  func chooseMimicReference() {
    guard !mimicIsPreparing, !isRecording, !isCapturingMimicReference else { return }
    let panel = NSOpenPanel()
    panel.title = "Choose a Voice to Mimic"
    panel.message = "Import a clip, then trim a short excerpt."
    panel.prompt = "Use Clip"
    panel.allowedContentTypes = AudioImportService.allowedContentTypes
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

    cancelMimicPreparation()
    let id = UUID()
    mimicPreparationID = id
    mimicIsPreparing = true
    clearError()
    let staged = FileManager.default.temporaryDirectory.appendingPathComponent(
      "voice-coach-mimic-\(id).wav")
    Task {
      do {
        try await AudioImportService.prepareAudio(from: sourceURL, to: staged)
        guard mimicPreparationID == id else {
          try? FileManager.default.removeItem(at: staged)
          return
        }
        presentMimicDraft(
          id: id,
          url: staged,
          sourceName: sourceURL.deletingPathExtension().lastPathComponent,
          source: AudioImportService.source(for: sourceURL)
        )
      } catch {
        try? FileManager.default.removeItem(at: staged)
        if mimicPreparationID == id {
          mimicIsPreparing = false
          mimicPreparationID = nil
          presentError(
            title: "Mimic failed",
            error: error,
            fallback: "Couldn’t prepare this reference.")
        }
      }
    }
  }

  func cancelMimicPreparation() {
    if isCapturingMimicReference {
      systemAudioCapture.stop()
      stopMimicReferenceCaptureTimer()
      if let url = mimicReferenceCaptureURL {
        try? FileManager.default.removeItem(at: url)
      }
      isCapturingMimicReference = false
      mimicReferenceCaptureURL = nil
      mimicReferenceCaptureStartedAt = nil
      clearMimicReferenceCaptureMeters()
    }
    mimicPreparationID = nil
    mimicIsPreparing = false
    stopPlayback()
    if let url = mimicDraft?.url { try? FileManager.default.removeItem(at: url) }
    mimicDraft = nil
  }

  func createMimicSession(name: String, start: Double, end: Double) {
    guard let draft = mimicDraft, !mimicIsPreparing,
      start >= 0, end <= draft.duration + 0.02, end - start >= 1,
      let activeID = mimicPreparationID
    else { return }
    mimicIsPreparing = true
    stopPlayback()
    let sessionID = UUID()
    let referenceID = UUID()
    let preferredEngine = transcriptionEngine
    // Precedence for titles: user-entered name > LLM > sourceName.
    let trimmedUserName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let userProvidedCustomName = !trimmedUserName.isEmpty && trimmedUserName != draft.sourceName
    let fallbackName = trimmedUserName.isEmpty ? draft.sourceName : trimmedUserName
    do {
      let destinationURL = try store.referenceURL(sessionID: sessionID)
      Task {
        do {
          let acoustic = try await Task.detached(priority: .userInitiated) {
            try AudioImportService.trimAudio(
              from: draft.url, to: destinationURL, start: start, end: end)
            return try AudioAnalyzer().analyze(url: destinationURL)
          }.value
          var transcription: TranscriptionResult?
          var words: [WordAnalysis] = []
          do {
            let outcome = try await TranscriptionService(preferredEngine: preferredEngine)
              .transcribe(url: destinationURL)
            transcription = outcome.result
            words = WordAcousticAnalyzer().analyze(transcription: outcome.result, result: acoustic)
          } catch {
            transcriptionNotice = Self.userFacingMessage(
              error, fallback: "Transcription failed.")
          }
          // Cancel check after ASR, before insert — never insert after dismiss.
          guard mimicPreparationID == activeID else {
            try? store.deleteSessionData(sessionID: sessionID)
            return
          }
          let referenceTake = PracticeSession(
            id: referenceID, audioURL: destinationURL,
            source: draft.source, result: acoustic,
            transcription: transcription, words: words
          )
          let session = CoachingSession(
            id: sessionID,
            name: fallbackName,
            mode: .mimic, prompt: "", keepsRecordings: true,
            mimicReference: MimicReference(
              sourceName: fallbackName, take: referenceTake,
              sourceStart: start, sourceEnd: end
            ), mimicStyle: .listenAndRepeat, mimicAttemptStyles: [:]
          )
          sessions.insert(session, at: 0)
          guard persist(analysisTakeIDs: [referenceID]) else {
            sessions.removeAll { $0.id == sessionID }
            try? store.deleteSessionData(sessionID: sessionID)
            mimicIsPreparing = false
            return
          }
          lastUsedMimicID = sessionID
          selectedSessionID = sessionID
          selectedTakeID = nil
          mimicWorkspaceMode = .practice
          destination = .practice(sessionID)
          cancelMimicPreparation()

          if !userProvidedCustomName, let text = transcription?.text {
            scheduleDeferredSmartTitle(
              sessionID: sessionID,
              fallbackName: fallbackName,
              transcript: text,
              syncMimicSourceName: true
            )
          }
        } catch {
          try? store.deleteSessionData(sessionID: sessionID)
          if mimicPreparationID == activeID {
            mimicIsPreparing = false
            presentError(
              title: "Mimic failed",
              error: error,
              fallback: "Couldn’t start this Mimic.")
          }
        }
      }
    } catch {
      mimicIsPreparing = false
      presentError(
        title: "Mimic failed",
        message: "Couldn’t create a local file for this reference.")
    }
  }

  func updateMimicStyle(_ style: MimicStyle) {
    guard !isRecording, !isAnalyzing, mimicPhase == .ready,
      let id = selectedSessionID, let index = sessions.firstIndex(where: { $0.id == id }),
      sessions[index].mode == .mimic
    else { return }
    let prior = sessions[index].mimicStyle
    sessions[index].mimicStyle = style
    if !persist() { sessions[index].mimicStyle = prior }
  }

  func startMimicPractice(skipReference: Bool = false) {
    guard !isRecording, !isPlaying, !isAnalyzing, !isRequestingPermission,
      mimicPhase == .ready, !hasPendingMimicWork,
      let reference = selectedSession?.mimicReference
    else { return }
    guard FileManager.default.fileExists(atPath: reference.take.audioURL.path) else {
      presentError(
        title: "Reference Missing",
        message: "Previous takes are still available in Analysis.")
      return
    }
    let begin: @MainActor () -> Void = { [weak self] in
      guard let self else { return }
      self.mimicWorkspaceMode = .practice
      if self.selectedSession?.mimicStyle == .speakAlong || skipReference {
        self.startMimicCountIn()
      } else {
        self.mimicShouldRecordAfterPlayback = true
        self.mimicPhase = .playingReference
        self.playMimicReference()
      }
    }
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: begin()
    case .notDetermined:
      isRequestingPermission = true
      AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
        Task { @MainActor in
          guard let self else { return }
          self.isRequestingPermission = false
          if granted {
            begin()
          } else {
            self.presentError(
              title: "Microphone Access Needed",
              message: RecorderError.microphoneDenied.errorDescription
                ?? "Turn on Voice Coach in System Settings → Privacy & Security → Microphone.")
          }
        }
      }
    default:
      presentError(
        title: "Microphone Access Needed",
        message: RecorderError.microphoneDenied.errorDescription
          ?? "Turn on Voice Coach in System Settings → Privacy & Security → Microphone.")
    }
  }

  func cancelMimicCountIn() {
    guard case .countIn = mimicPhase else { return }
    mimicCountInTask?.cancel()
    mimicPhase = .ready
  }

  private func startMimicCountIn() {
    mimicPhase = .countIn(2)
    mimicCountInTask?.cancel()
    mimicCountInTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(1))
      guard let self, !Task.isCancelled else { return }
      self.mimicPhase = .countIn(1)
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled else { return }
      self.mimicAlong = self.selectedSession?.mimicStyle == .speakAlong
      self.beginRecording()
      if !self.isRecording { self.mimicPhase = .ready }
    }
  }

  func playMimicReference(range: ClosedRange<Double>? = nil) {
    guard let reference = selectedSession?.mimicReference, !isRecording else { return }
    let bounds = range ?? 0...reference.take.result.metrics.duration
    playMimicSegment(
      url: reference.take.audioURL, source: .reference, start: bounds.lowerBound,
      end: bounds.upperBound)
  }

  func playMimicDraft(start: Double, end: Double) {
    guard let mimicDraft, !mimicIsPreparing else { return }
    playMimicSegment(url: mimicDraft.url, source: .reference, start: start, end: end)
  }

  func playMimicAttempt(range: ClosedRange<Double>? = nil) {
    guard let take = selectedTake, !isRecording else { return }
    let bounds = range ?? 0...take.result.metrics.duration
    playMimicSegment(
      url: take.audioURL, source: .attempt, start: bounds.lowerBound, end: bounds.upperBound)
  }

  func seekMimic(source: MimicPlaybackSource, to time: Double) {
    guard !isRecording, !isAnalyzing, mimicPhase == .ready else { return }
    let take = source == .reference ? selectedSession?.mimicReference?.take : selectedTake
    guard let take else { return }
    let duration = take.result.metrics.duration
    guard duration > 0 else { return }
    let start = min(max(0, time), max(0, duration - 0.05))
    playMimicSegment(url: take.audioURL, source: source, start: start, end: duration)
  }

  func retryPendingMimicWork() {
    guard hasPendingMimicWork else { return }
    if let pendingMimicTake {
      append(pendingMimicTake)
    } else if let pendingMimicAudio {
      analyze(url: pendingMimicAudio.url, takeID: pendingMimicAudio.id)
    }
  }

  func revealPendingMimicAudio() {
    let url = pendingMimicTake?.audioURL ?? pendingMimicAudio?.url
    if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
  }

  func stepMimicTake(by delta: Int) {
    guard let session = selectedSession, session.mode == .mimic,
      !isRecording, mimicPhase == .ready,
      let current = selectedTakeID.flatMap({ id in session.takes.firstIndex(where: { $0.id == id })
      }),
      session.takes.indices.contains(current + delta)
    else { return }
    selectTake(session.takes[current + delta].id)
  }

  func toggleMimicPlayback() {
    guard isMimicWorkspace, !isRecording else { return }
    if mimicPhase == .playingReference {
      stopPlayback()
      return
    }
    guard mimicPhase == .ready else { return }
    if mimicWorkspaceMode == .analysis {
      playCurrent()
      return
    }
    if isPlaying {
      pausePlayback()
      return
    }
    let source: MimicPlaybackSource =
      mimicWorkspaceMode == .compare ? mimicPlaybackSource : .reference
    let take = source == .reference ? selectedSession?.mimicReference?.take : selectedTake
    guard let take else { return }
    let start = source == mimicPlaybackSource ? playbackTime : 0
    if start <= 0 || start >= take.result.metrics.duration - 0.05 {
      seekMimic(source: source, to: 0)
      return
    }
    do {
      recorder.playbackVolume = source == .reference ? Float(mimicReferenceVolume) : 1
      try recorder.play(url: take.audioURL, from: start)
      mimicPlaybackSource = source
      mimicPlaybackEnd = mimicPlaybackEnd ?? take.result.metrics.duration
      isPlaying = true
      startPlaybackTimer()
    } catch {
      presentError(
        title: "Playback failed",
        message: "This clip couldn’t be played.")
    }
  }

  private func playMimicSegment(url: URL, source: MimicPlaybackSource, start: Double, end: Double) {
    guard !isRecording, end > start else { return }
    recorder.stopPlayback()
    stopPlaybackTimer()
    do {
      recorder.playbackVolume = source == .reference ? Float(mimicReferenceVolume) : 1
      try recorder.play(url: url, from: start)
      mimicPlaybackSource = source
      mimicPlaybackEnd = end
      isPlaying = true
      playbackTime = start
      startPlaybackTimer()
    } catch {
      mimicShouldRecordAfterPlayback = false
      mimicPhase = .ready
      presentError(
        title: "Playback failed",
        message: "This clip couldn’t be played.")
    }
  }

  func finishMimicPlayback() {
    stopPlaybackTimer()
    isPlaying = false
    playbackTime = 0
    mimicPlaybackEnd = nil
    if mimicShouldRecordAfterPlayback {
      mimicShouldRecordAfterPlayback = false
      startMimicCountIn()
    } else if mimicAlong && isRecording {
      mimicCountInTask?.cancel()
      mimicCountInTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(1.5))
        guard let self, !Task.isCancelled, self.isRecording else { return }
        self.stopRecording()
      }
    } else if mimicPhase == .playingReference {
      mimicPhase = .ready
    }
  }
}
