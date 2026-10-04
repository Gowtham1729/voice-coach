import AppKit
import Foundation
import VoiceCoachCore

extension AppModel {
  func refreshTranscriptionSetupStatus() {
    guard !transcriptionSetupStatus.isBusy else { return }
    transcriptionSetupStatus = TranscriptionSetupService.currentStatus()
  }

  var transcriptionLocale: Locale {
    TranscriptionLanguagePreference.locale(for: transcriptionLocaleIdentifier)
  }

  var newSessionTranscriptionLocale: Locale? {
    TranscriptionLanguagePreference.requestedLocale(
      for: transcriptionLocaleIdentifier, engine: transcriptionEngine)
  }

  func setTranscriptionLanguage(_ identifier: String) {
    guard !isRecording, !isAnalyzing, !mimicIsPreparing,
      !systemTranscriptionStatus.isBusy
    else { return }
    transcriptionLocaleIdentifier = identifier
    UserDefaults.standard.set(identifier, forKey: TranscriptionLanguagePreference.storageKey)
    refreshSystemTranscriptionStatus()
  }

  func refreshSystemTranscriptionStatus() {
    guard !systemTranscriptionStatus.isBusy else { return }
    systemTranscriptionStatusTask?.cancel()
    let preferredLocale = transcriptionLocale
    isCheckingSpeechLanguages = true
    systemTranscriptionStatusTask = Task { @MainActor [weak self] in
      let locales = await AppleSpeechTranscriber.supportedLocales()
      let status = await AppleSpeechTranscriber.currentStatus(preferredLocale: preferredLocale)
      guard !Task.isCancelled, let self else { return }
      supportedSpeechLocales = locales.map(\.identifier).sorted {
        TranscriptionLanguagePreference.displayName(for: $0)
          .localizedStandardCompare(TranscriptionLanguagePreference.displayName(for: $1))
          == .orderedAscending
      }
      systemTranscriptionStatus = status
      isCheckingSpeechLanguages = false
    }
  }

  func setTranscriptionEngine(_ engine: TranscriptionEnginePreference) {
    transcriptionEngine = engine
    engine.save()
    toastMessage = "Using \(engine == .system ? "System" : "Parakeet") transcription"
  }

  func ensureSystemTranscriptionAssets() {
    guard !systemTranscriptionStatus.isBusy else { return }
    guard !isRecording, !isAnalyzing else {
      presentError(
        title: "Download Unavailable",
        message: "Finish recording or analysis first.")
      return
    }
    if case .ready = systemTranscriptionStatus {
      toastMessage = "System transcription is ready"
      return
    }

    let preferredLocale = transcriptionLocale
    let locale: String
    if case .needsDownload(let identifier) = systemTranscriptionStatus {
      locale = identifier
    } else {
      locale = preferredLocale.identifier
    }

    systemAssetInstallTask?.cancel()
    systemTranscriptionStatus = .downloading(localeIdentifier: locale)
    systemAssetInstallTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await AppleSpeechTranscriber.ensureAssets(preferredLocale: preferredLocale)
        guard !Task.isCancelled else { return }
        systemTranscriptionStatus = await AppleSpeechTranscriber.currentStatus(
          preferredLocale: preferredLocale)
        if systemTranscriptionStatus.isReady {
          toastMessage = "System transcription is ready"
        }
      } catch is CancellationError {
        refreshSystemTranscriptionStatus()
      } catch {
        systemTranscriptionStatus = await AppleSpeechTranscriber.currentStatus(
          preferredLocale: preferredLocale)
        presentError(
          title: "Download failed",
          error: error,
          fallback: "Couldn’t download the speech model.")
      }
    }
  }

  func startTranscriptionSetup() {
    guard !transcriptionSetupStatus.isBusy else { return }
    guard !isRecording, !isAnalyzing else {
      presentError(
        title: "Download Unavailable",
        message: "Finish recording or analysis first.")
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
        transcriptionSetupStatus = .failed(
          Self.userFacingMessage(error, fallback: "Couldn’t install Parakeet."))
        presentError(
          title: "Download failed",
          error: error,
          fallback: "Couldn’t install Parakeet.")
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
