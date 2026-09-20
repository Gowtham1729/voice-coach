import AVFoundation
import AppKit
import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  func captureMimicReferencePressed() {
    guard !mimicIsPreparing, !isRecording, !isAnalyzing else { return }
    if isCapturingMimicReference {
      finishMimicReferenceCapture()
      return
    }
    beginMimicReferenceCapture()
  }

  private func beginMimicReferenceCapture() {
    cancelMimicPreparation()

    let id = UUID()
    mimicPreparationID = id
    let staged = FileManager.default.temporaryDirectory
      .appendingPathComponent("voice-coach-mimic-system-\(id).wav")
    do {
      try systemAudioCapture.start(url: staged)
      mimicReferenceCaptureURL = staged
      mimicReferenceCaptureStartedAt = Date()
      mimicReferenceCaptureElapsed = 0
      mimicReferenceCaptureLevel = -80
      isCapturingMimicReference = true
      clearError()
      toastMessage = nil
      startMimicReferenceCaptureTimer()
    } catch {
      try? FileManager.default.removeItem(at: staged)
      mimicPreparationID = nil
      presentError(
        title: "Capture failed",
        error: error,
        fallback: "Couldn’t capture Mac audio.")
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
      clearMimicReferenceCaptureMeters()
      return
    }

    if elapsedCapture < 0.6 {
      failMimicReferenceCapture(
        url: url,
        message: "Capture at least one second of Mac audio.")
      )
      return
    }
    if !heardAudio {
      failMimicReferenceCapture(
        url: url,
        message: SystemAudioCaptureError.permissionOrSilent.localizedDescription
      )
      return
    }

    presentMimicDraft(id: id, url: url, sourceName: "Mac Audio", source: .systemAudio)
  }

  private func failMimicReferenceCapture(url: URL, message: String) {
    try? FileManager.default.removeItem(at: url)
    presentError(title: "Capture failed", message: message)
    clearMimicReferenceCaptureMeters()
    mimicPreparationID = nil
  }

  func clearMimicReferenceCaptureMeters() {
    mimicReferenceCaptureElapsed = 0
    mimicReferenceCaptureLevel = -80
  }

  func startMimicReferenceCaptureTimer() {
    stopMimicReferenceCaptureTimer()
    mimicReferenceCaptureTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
      [weak self] _ in
      Task { @MainActor in
        guard let self, self.isCapturingMimicReference else { return }
        self.mimicReferenceCaptureElapsed = Date().timeIntervalSince(
          self.mimicReferenceCaptureStartedAt ?? Date())
        self.mimicReferenceCaptureLevel = Double(self.systemAudioCapture.peakLevel())
        if self.mimicReferenceCaptureElapsed >= 90 {
          self.finishMimicReferenceCapture()
        }
      }
    }
  }

  func stopMimicReferenceCaptureTimer() {
    mimicReferenceCaptureTimer?.invalidate()
    mimicReferenceCaptureTimer = nil
  }

  /// Shared path for file import and Mac-audio capture → trim-ready draft.
  func presentMimicDraft(id: UUID, url: URL, sourceName: String, source: TakeSource) {
    mimicIsPreparing = true
    clearError()
    Task {
      do {
        let overview = try await Task.detached(priority: .userInitiated) {
          try AudioImportService.waveform(from: url)
        }.value
        guard mimicPreparationID == id else {
          try? FileManager.default.removeItem(at: url)
          return
        }
        mimicDraft = MimicReferenceDraft(
          id: id,
          url: url,
          sourceName: sourceName,
          duration: overview.duration,
          peaks: overview.peaks,
          source: source
        )
        mimicIsPreparing = false
        clearMimicReferenceCaptureMeters()
      } catch {
        try? FileManager.default.removeItem(at: url)
        if mimicPreparationID == id {
          mimicIsPreparing = false
          mimicPreparationID = nil
          clearMimicReferenceCaptureMeters()
          presentError(
            title: "Mimic failed",
            error: error,
            fallback: "Couldn’t prepare this reference.")
        }
      }
    }
  }
}
