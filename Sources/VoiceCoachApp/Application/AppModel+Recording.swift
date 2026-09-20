import AVFoundation
import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  func requestPermissionAndRecord() {
    if selectedSessionID == nil {
      prepareStandaloneCapture()
    }
    guard selectedSessionID != nil else { return }
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: beginRecording()
    case .notDetermined:
      isRequestingPermission = true
      AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
        Task { @MainActor in
          guard let self else { return }
          self.isRequestingPermission = false
          if granted {
            self.beginRecording()
          } else {
            self.discardPendingStandaloneIfEmpty()
            self.presentError(
              title: "Microphone Access Needed",
              message: RecorderError.microphoneDenied.localizedDescription ?? "")
          }
        }
      }
    default:
      discardPendingStandaloneIfEmpty()
      presentError(
        title: "Microphone Access Needed",
        message: RecorderError.microphoneDenied.localizedDescription ?? "")
    }
  }

  func prepareStandaloneCapture() {
    discardPendingStandaloneIfEmpty()
    let id = UUID()
    pendingCaptureIsNewSession = true
    selectedSessionID = id
    do {
      _ = try store.takeDirectory(sessionID: id)
    } catch {
      pendingCaptureIsNewSession = false
      selectedSessionID = nil
      presentError(
        title: "Recording failed",
        message: "Couldn’t create a local file for this recording.")
    }
  }

  func discardPendingStandaloneIfEmpty() {
    guard pendingCaptureIsNewSession, let id = selectedSessionID,
      !sessions.contains(where: { $0.id == id })
    else {
      pendingCaptureIsNewSession = false
      pendingImportSourceURL = nil
      return
    }
    try? store.deleteSessionData(sessionID: id)
    pendingCaptureIsNewSession = false
    pendingImportSourceURL = nil
    if selectedSessionID == id { selectedSessionID = nil }
  }

  func beginRecording() {
    guard let sessionID = selectedSessionID else { return }
    guard !isRecording, !isCapturingMimicReference else { return }
    if !mimicAlong {
      recorder.stopPlayback()
      isPlaying = false
    }
    do {
      let takeID = UUID()
      let url = try store.recordingURL(sessionID: sessionID, takeID: takeID)
      try recorder.start(url: url)
      recordingURL = url
      recordingTakeID = takeID
      startedAt = Date()
      elapsed = 0
      liveLevel = -80
      isRecording = true
      if sessions.first(where: { $0.id == sessionID })?.mode == .mimic {
        mimicPhase = .recording
      }
      isAnalyzing = false
      clearError()
      toastMessage = nil
      transcriptionNotice = nil
      startTimer()
      if mimicAlong, let reference = selectedSession?.mimicReference {
        do {
          recorder.playbackVolume = Float(mimicReferenceVolume)
          try recorder.play(url: reference.take.audioURL)
          mimicPlaybackSource = .reference
          isPlaying = true
          startPlaybackTimer()
        } catch {
          recorder.stop()
          timer?.invalidate()
          timer = nil
          isRecording = false
          mimicPhase = .ready
          presentError(
            title: "Playback failed",
            message: "Couldn’t play the reference while recording.")
          if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
          recordingURL = nil
          recordingTakeID = nil
        }
      }
    } catch {
      presentError(
        title: "Recording failed",
        error: error,
        fallback: "Couldn’t start recording. Check that a microphone is connected.")
    }
  }

  func stopRecording() {
    mimicCountInTask?.cancel()
    let wasMimic = selectedSession?.mode == .mimic
    if wasMimic {
      recorder.stopPlayback()
      stopPlaybackTimer()
      isPlaying = false
      mimicAlong = false
    }
    recorder.stop()
    timer?.invalidate()
    timer = nil
    isRecording = false
    if wasMimic { mimicPhase = .analyzing }
    guard elapsed >= 0.6, let url = recordingURL, let takeID = recordingTakeID else {
      presentError(
        title: "Recording Too Short",
        message: "Record at least one second.")
      if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
      recordingURL = nil
      recordingTakeID = nil
      mimicPhase = .ready
      discardPendingStandaloneIfEmpty()
      return
    }
    analyze(url: url, takeID: takeID)
  }

  // MARK: - Mimic reference Mac audio

  func analyze(url: URL, takeID: UUID, source: TakeSource = .recorded) {
    isAnalyzing = true
    let preferredEngine = transcriptionEngine
    let captureIsNewSession = pendingCaptureIsNewSession
    let captureImportURL = pendingImportSourceURL
    let captureSessionID = selectedSessionID
    Task {
      do {
        let acoustic = try await Task.detached(priority: .userInitiated) {
          try AudioAnalyzer().analyze(url: url)
        }.value

        var transcription: TranscriptionResult?
        var words: [WordAnalysis] = []
        var notice: String?
        do {
          let outcome = try await TranscriptionService(preferredEngine: preferredEngine)
            .transcribe(url: url)
          transcription = outcome.result
          words = WordAcousticAnalyzer().analyze(
            transcription: outcome.result,
            result: acoustic
          )
          notice = outcome.notice
        } catch {
          notice = Self.userFacingMessage(error, fallback: "Transcription failed.")
        }

        let take = PracticeSession(
          id: takeID,
          audioURL: url,
          source: source,
          result: acoustic,
          transcription: transcription,
          words: words
        )

        finishAnalyzeCleanup()
        append(take)
        transcriptionNotice = notice
        maybeScheduleSmartTitleAfterStandaloneSave(
          captureIsNewSession: captureIsNewSession,
          captureImportURL: captureImportURL,
          captureSessionID: captureSessionID,
          source: source,
          take: take,
          transcript: transcription?.text
        )
      } catch {
        presentError(
          title: "Analysis failed",
          error: error,
          fallback: "Couldn’t analyze this recording. Try again.")
        if selectedSession?.mode == .mimic {
          pendingMimicAudio = (url, takeID)
          pendingMimicSessionID = selectedSessionID
        } else if pendingCaptureIsNewSession {
          pendingImportSourceURL = nil
        }
        finishAnalyzeCleanup()
      }
    }
  }

  private func finishAnalyzeCleanup() {
    isAnalyzing = false
    mimicPhase = .ready
    recordingURL = nil
    recordingTakeID = nil
  }

  private func maybeScheduleSmartTitleAfterStandaloneSave(
    captureIsNewSession: Bool,
    captureImportURL: URL?,
    captureSessionID: UUID?,
    source: TakeSource,
    take: PracticeSession,
    transcript: String?
  ) {
    let isMicStandalone = captureIsNewSession && captureImportURL == nil && source == .recorded
    guard isMicStandalone,
      let sessionID = captureSessionID,
      let text = transcript
    else { return }

    let fallbackName = RecordingTitle.make(date: take.createdAt)
    guard sessions.first(where: { $0.id == sessionID })?.name == fallbackName else { return }
    scheduleDeferredSmartTitle(
      sessionID: sessionID,
      fallbackName: fallbackName,
      transcript: text,
      syncMimicSourceName: false
    )
  }

  /// Fire-and-forget naming after the take/Mimic UI is already interactive.
  func scheduleDeferredSmartTitle(
    sessionID: UUID,
    fallbackName: String,
    transcript: String,
    syncMimicSourceName: Bool
  ) {
    guard AutoTitlePreference.isEnabled else { return }
    guard SmartTitleRules.transcriptPassesGates(transcript) else { return }

    isSuggestingTitle = true
    Task.detached(priority: .utility) { [weak self] in
      try? await Task.sleep(for: .milliseconds(150))
      let suggested = await SmartTitleGenerator.suggestTitle(from: transcript)
      await self?.finishDeferredSmartTitle(
        sessionID: sessionID,
        fallbackName: fallbackName,
        suggested: suggested,
        syncMimicSourceName: syncMimicSourceName
      )
    }
  }

  private func finishDeferredSmartTitle(
    sessionID: UUID,
    fallbackName: String,
    suggested: String?,
    syncMimicSourceName: Bool
  ) {
    defer { isSuggestingTitle = false }
    guard let suggested,
      let index = sessions.firstIndex(where: { $0.id == sessionID }),
      sessions[index].name == fallbackName
    else { return }
    if syncMimicSourceName {
      guard sessions[index].mimicReference?.sourceName == fallbackName else { return }
    }
    renameSession(sessionID, to: suggested)
  }

  func append(_ take: PracticeSession) {
    guard let selectedSessionID else { return }

    if pendingCaptureIsNewSession, !sessions.contains(where: { $0.id == selectedSessionID }) {
      appendStandalone(take, sessionID: selectedSessionID)
      return
    }

    guard let index = sessions.firstIndex(where: { $0.id == selectedSessionID }) else { return }
    let previousSessions = sessions
    var recordingsToReplace: [URL] = []
    if sessions[index].keepsRecordings || sessions[index].mode == .mimic {
      sessions[index].takes.append(take)
      if sessions[index].mode == .mimic {
        if sessions[index].mimicAttemptStyles == nil { sessions[index].mimicAttemptStyles = [:] }
        sessions[index].mimicAttemptStyles?[take.id] =
          sessions[index].mimicStyle ?? .listenAndRepeat
      }
    } else {
      recordingsToReplace = sessions[index].takes.map(\.audioURL)
      sessions[index].takes = [take]
    }
    sessions[index].updatedAt = Date()
    selectedTakeID = take.id
    sortSessions()
    guard persist(analysisTakeIDs: [take.id]) else {
      sessions = previousSessions
      selectedTakeID = previousSessions.first(where: { $0.id == selectedSessionID })?.latestTake?.id
      if sessions.first(where: { $0.id == selectedSessionID })?.mode == .mimic {
        pendingMimicTake = take
        pendingMimicSessionID = selectedSessionID
        presentError(
          title: "Save failed",
          message: "The recording is still on this Mac. Retry Save, or show the audio file.")
      }
      return
    }
    if pendingMimicSessionID == selectedSessionID {
      pendingMimicTake = nil
      pendingMimicAudio = nil
      pendingMimicSessionID = nil
    }
    for url in recordingsToReplace where url != take.audioURL {
      try? FileManager.default.removeItem(at: url)
    }
    toastMessage = saveToast(for: take.takeSource)
    if sessions[index].mode == .mimic {
      lastUsedMimicID = selectedSessionID
      mimicWorkspaceMode = .compare
      destination = .practice(selectedSessionID)
    } else {
      destination = .take(selectedSessionID, take.id)
    }
  }

  private func appendStandalone(_ take: PracticeSession, sessionID: UUID) {
    let name: String
    if let source = pendingImportSourceURL {
      name = source.deletingPathExtension().lastPathComponent
    } else {
      name = RecordingTitle.make(date: take.createdAt)
    }
    let session = CoachingSession(
      id: sessionID,
      name: name,
      mode: .general,
      prompt: "",
      keepsRecordings: true,
      takes: [take]
    )
    sessions.insert(session, at: 0)
    selectedTakeID = take.id
    pendingCaptureIsNewSession = false
    pendingImportSourceURL = nil
    sortSessions()
    guard persist(analysisTakeIDs: [take.id]) else {
      sessions.removeAll { $0.id == sessionID }
      selectedTakeID = nil
      presentError(
        title: "Save failed",
        message: "The recording is still on this Mac but wasn’t added to the library.")
      return
    }
    toastMessage = saveToast(for: take.takeSource)
    destination = .take(sessionID, take.id)
  }

  func sortSessions() { sessions.sort { $0.updatedAt > $1.updatedAt } }

  private func saveToast(for source: TakeSource) -> String {
    switch source {
    case .recorded: "Recording saved"
    case .importedAudio, .importedVideo: "Import saved"
    case .systemAudio: "Mac audio saved"
    }
  }

  /// Persists the thin session index. Pass take IDs whose analysis blobs changed;
  /// omit (default empty) for metadata-only updates such as rename or Mimic style.
  @discardableResult
  func persist(analysisTakeIDs: Set<UUID> = []) -> Bool {
    do {
      try store.save(sessions, analysisTakeIDs: analysisTakeIDs)
      return true
    } catch {
      presentError(title: "Save failed", message: "Couldn’t update the library.")
      return false
    }
  }

  private func startTimer() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.elapsed = Date().timeIntervalSince(self.startedAt ?? Date())
        self.liveLevel = Double(self.recorder.peakLevel())
        if self.elapsed >= 90 { self.stopRecording() }
      }
    }
  }

  func startPlaybackTimer() {
    playbackTimer?.invalidate()
    playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.isPlaying else { return }
        self.playbackTime = self.recorder.currentTime
        if let end = self.mimicPlaybackEnd, self.playbackTime >= end {
          self.recorder.stopPlayback()
          self.finishMimicPlayback()
        }
      }
    }
  }

  func stopPlaybackTimer() {
    playbackTimer?.invalidate()
    playbackTimer = nil
  }
}
