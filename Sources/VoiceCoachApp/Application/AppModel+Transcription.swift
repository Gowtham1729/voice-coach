import AppKit
import Foundation
import VoiceCoachCore

extension AppModel {
  func refreshTranscriptionSetupStatus() {
    guard !transcriptionSetupStatus.isBusy else { return }
    transcriptionSetupStatus = TranscriptionSetupService.currentStatus()
  }

  func refreshSystemTranscriptionStatus() {
    guard !systemTranscriptionStatus.isBusy else { return }
    systemTranscriptionStatusTask?.cancel()
    systemTranscriptionStatusTask = Task { @MainActor [weak self] in
      let status = await AppleSpeechTranscriber.currentStatus()
      guard !Task.isCancelled else { return }
      self?.systemTranscriptionStatus = status
    }
  }

  func setTranscriptionEngine(_ engine: TranscriptionEnginePreference) {
    transcriptionEngine = engine
    engine.save()
    toastMessage = "Transcription engine set to \(engine.title)"
  }

  func ensureSystemTranscriptionAssets() {
    guard !systemTranscriptionStatus.isBusy else { return }
    guard !isRecording, !isAnalyzing else {
      errorMessage = "Finish recording or analysis before downloading speech models."
      return
    }
    if case .ready = systemTranscriptionStatus {
      toastMessage = "System transcription is already ready"
      return
    }

    let locale: String
    if case .needsDownload(let identifier) = systemTranscriptionStatus {
      locale = identifier
    } else {
      locale = Locale.current.identifier
    }

    systemAssetInstallTask?.cancel()
    systemTranscriptionStatus = .downloading(localeIdentifier: locale)
    systemAssetInstallTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await AppleSpeechTranscriber.ensureAssets()
        guard !Task.isCancelled else { return }
        systemTranscriptionStatus = await AppleSpeechTranscriber.currentStatus()
        if systemTranscriptionStatus.isReady {
          toastMessage = "System transcription is ready"
        }
      } catch is CancellationError {
        refreshSystemTranscriptionStatus()
      } catch {
        systemTranscriptionStatus = .unavailable(error.localizedDescription)
        errorMessage = error.localizedDescription
      }
    }
  }

  func startTranscriptionSetup() {
    guard !transcriptionSetupStatus.isBusy else { return }
    guard !isRecording, !isAnalyzing else {
      errorMessage = "Finish recording or analysis before downloading transcription."
      return
    }

    transcriptionSetupTask?.cancel()
    transcriptionSetupStatus = .installing(.preparing)
    transcriptionSetupTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await TranscriptionSetupService().installOrUpdate { phase in
          Task { @MainActor in
            self.transcriptionSetupStatus = .installing(phase)
          }
        }
        guard !Task.isCancelled else { return }
        transcriptionSetupStatus = TranscriptionSetupService.currentStatus()
        if transcriptionSetupStatus.isReady {
          toastMessage = "Parakeet transcription is ready"
        }
      } catch is CancellationError {
        refreshTranscriptionSetupStatus()
      } catch {
        transcriptionSetupStatus = .failed(error.localizedDescription)
        errorMessage = error.localizedDescription
      }
    }
  }

  func revealTranscriptionInstall() {
    if let managed = try? TranscriptionSetupService.managedRuntimePrefixURL(),
      FileManager.default.fileExists(atPath: managed.path)
    {
      NSWorkspace.shared.activateFileViewerSelecting([managed])
      return
    }
    if case .ready(let path, _) = transcriptionSetupStatus {
      NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([storageLocation])
  }
}
