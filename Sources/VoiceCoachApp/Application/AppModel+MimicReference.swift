import AVFoundation
import AppKit
import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  func captureMimicReferencePressed(fromMenuBar: Bool = false) {
    guard !mimicIsPreparing, !isRecording, !isAnalyzing, !isRequestingPermission,
      mimicPhase == .ready, !hasPendingMimicWork
    else { return }
    if isCapturingMimicReference {
      finishMimicReferenceCapture()
      return
    }
    beginMimicReferenceCapture(fromMenuBar: fromMenuBar)
  }

  private func beginMimicReferenceCapture(fromMenuBar: Bool) {
    cancelMimicPreparation()

    let id = UUID()
    mimicPreparationID = id
    let staged = FileManager.default.temporaryDirectory
      .appendingPathComponent("voice-coach-mimic-system-\(id).wav")
    mimicReferenceCaptureURL = staged
    hasMenuBarReference = fromMenuBar
    isRequestingPermission = true
    clearError()
    toastMessage = nil
    systemAudioCapture.requestStart(url: staged) { [weak self, capture = systemAudioCapture] result in
      // A cancelled request no longer owns `mimicPreparationID`. Tear its tap down
      // unless a newer capture has since taken over the shared service.
      guard let self, self.mimicPreparationID == id else {
        if self?.mimicReferenceCaptureURL == nil { capture.stop() }
        try? FileManager.default.removeItem(at: staged)
        return
      }
      self.isRequestingPermission = false
      switch result {
      case .success:
        self.mimicReferenceCaptureStartedAt = Date()
        self.mimicReferenceCaptureElapsed = 0
        self.mimicReferenceCaptureLevel = -80
        self.isCapturingMimicReference = true
        self.startMimicReferenceCaptureTimer()
      case .failure(let error):
        try? FileManager.default.removeItem(at: staged)
        self.mimicReferenceCaptureURL = nil
        self.hasMenuBarReference = false
        self.mimicPreparationID = nil
        self.presentCaptureError(
          title: "Capture failed", error: error, fallback: "Couldn’t capture Mac audio.")
      }
    }
  }

  func finishMimicReferenceCapture() {
    let elapsedCapture = mimicReferenceCaptureElapsed
    let heardAudio = systemAudioCapture.heardAudio
    let url = mimicReferenceCaptureURL
    let id = mimicPreparationID

    systemAudioCapture.stop()
    stopMimicReferenceCaptureTimer()
    isCapturingMimicReference = false
    mimicReferenceCaptureURL = nil
    mimicReferenceCaptureStartedAt = nil

    guard let url, let id else {
      hasMenuBarReference = false
      clearMimicReferenceCaptureMeters()
      return
    }

    if elapsedCapture < 0.6 {
      failMimicReferenceCapture(
        url: url,
        message: "Capture at least one second of Mac audio."
      )
      return
    }
    if !heardAudio {
      failMimicReferenceCapture(
        url: url,
        message: SystemAudioCaptureError.permissionOrSilent.errorDescription
          ?? "Play audio on this Mac, then capture again."
      )
      return
    }

    presentMimicDraft(id: id, url: url, sourceName: "Mac Audio", source: .systemAudio)
  }

  private func failMimicReferenceCapture(url: URL, message: String) {
    hasMenuBarReference = false
    try? FileManager.default.removeItem(at: url)
    presentCaptureError(title: "Capture failed", message: message)
    clearMimicReferenceCaptureMeters()
    mimicPreparationID = nil
  }

  func clearMimicReferenceCaptureMeters() {
    mimicReferenceCaptureElapsed = 0
    mimicReferenceCaptureLevel = -80
  }

  func startMimicReferenceCaptureTimer() {
    stopMimicReferenceCaptureTimer()
    let timer = Timer(timeInterval: 0.05, repeats: true) {
      [weak self] _ in
      Task { @MainActor in self?.tickMimicReferenceCapture() }
    }
    mimicReferenceCaptureTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  /// One timer tick: refresh the meters and stop automatically at 90 seconds.
  func tickMimicReferenceCapture() {
    guard isCapturingMimicReference else { return }
    mimicReferenceCaptureElapsed = Date().timeIntervalSince(mimicReferenceCaptureStartedAt ?? Date())
    mimicReferenceCaptureLevel = Double(systemAudioCapture.peakLevel())
    if mimicReferenceCaptureElapsed >= 90 { finishMimicReferenceCapture() }
  }

  func stopMimicReferenceCaptureTimer() {
    mimicReferenceCaptureTimer?.invalidate()
    mimicReferenceCaptureTimer = nil
  }

  /// Prepare phrases before creating any library entry.
  @discardableResult
  func presentMimicDraft(
    id: UUID, url: URL, sourceName: String, source: TakeSource,
    transcription: TranscriptionResult? = nil
  ) -> Task<Void, Never> {
    mimicIsPreparing = true
    clearError()
    let engine = transcriptionEngine
    let locale = newSessionTranscriptionLocale
    let task = Task {
      defer {
        if mimicPreparationID == id {
          mimicIsPreparing = false
          mimicIsFindingPhrases = false
          mimicPreparationTask = nil
          clearMimicReferenceCaptureMeters()
        }
      }
      do {
        let overview = try await Task.detached(priority: .userInitiated) {
          try AudioImportService.waveform(from: url)
        }.value
        guard mimicPreparationID == id else {
          try? FileManager.default.removeItem(at: url)
          return
        }
        guard overview.duration >= PracticeClipSelection.minimumDuration else {
          try? FileManager.default.removeItem(at: url)
          let fromMenuBar = hasMenuBarReference
          hasMenuBarReference = false
          mimicIsPreparing = false
          mimicIsFindingPhrases = false
          mimicPreparationTask = nil
          mimicPreparationID = nil
          clearMimicReferenceCaptureMeters()
          let message = "Use a clip of at least one second."
          if fromMenuBar {
            presentCaptureError(title: "Clip too short", message: message)
          } else {
            presentError(title: "Clip too short", message: message)
          }
          return
        }
        var recognized = transcription
        var notice: String?
        if recognized == nil {
          mimicIsFindingPhrases = true
          // Valid audio remains available for manual selection if speech recognition fails.
          let outcome = try? await transcribeForAnalysis(url: url, engine: engine, locale: locale)
          recognized = outcome?.transcription
          notice = outcome?.notice
        }
        try Task.checkCancellation()
        guard mimicPreparationID == id else {
          try? FileManager.default.removeItem(at: url)
          return
        }
        if let notice { transcriptionNotice = notice }
        mimicDraft = MimicReferenceDraft(
          id: id,
          url: url,
          sourceName: sourceName,
          duration: overview.duration,
          peaks: overview.peaks,
          source: source, transcription: recognized,
          transcriptionLocaleIdentifier: recognized?.localeIdentifier ?? locale?.identifier
        )
      } catch {
        try? FileManager.default.removeItem(at: url)
        if mimicPreparationID == id {
          let fromMenuBar = hasMenuBarReference
          hasMenuBarReference = false
          mimicIsPreparing = false
          mimicIsFindingPhrases = false
          mimicPreparationTask = nil
          mimicPreparationID = nil
          clearMimicReferenceCaptureMeters()
          if !(error is CancellationError) {
            let title = "Reference practice failed"
            let fallback = "Couldn’t prepare this reference."
            if fromMenuBar {
              presentCaptureError(title: title, error: error, fallback: fallback)
            } else {
              presentError(title: title, error: error, fallback: fallback)
            }
          }
        }
      }
    }
    mimicPreparationTask = task
    return task
  }
}
