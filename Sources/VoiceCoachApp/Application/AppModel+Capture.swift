import AppKit
import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  func recordButtonPressed() {
    if selectedSession?.isMimic == true, destination.isWorkspace {
      if isRecording { stopRecording() } else { startMimicPractice() }
      return
    }
    guard !isAnalyzing, !isRequestingPermission, !isCapturingMimicReference else { return }
    if isRecording {
      stopRecording()
      return
    }
    switch destination {
    case .home, .library, .mimics, .mimicStart:
      startHomeRecording()
    case .practice:
      startMimicPractice()
    case .take:
      recordAnother()
    }
  }

  func recordAnother() {
    guard let session = selectedSession, !session.isMimic else {
      startHomeRecording()
      return
    }
    if !session.keepsRecordings {
      pendingReplaceOnly = ReplaceOnlyPrompt(sessionID: session.id, kind: .record)
      return
    }
    requestPermissionAndRecord()
  }

  func confirmKeepAllFromNowOn() {
    guard let prompt = pendingReplaceOnly,
      let index = sessions.firstIndex(where: { $0.id == prompt.sessionID })
    else { return }
    sessions[index].keepsRecordings = true
    persist()
    continuePendingReplaceOnly(prompt)
  }

  func confirmReplaceOldest() {
    guard let prompt = pendingReplaceOnly else { return }
    continuePendingReplaceOnly(prompt)
  }

  private func continuePendingReplaceOnly(_ prompt: ReplaceOnlyPrompt) {
    let kind = prompt.kind
    let sessionID = prompt.sessionID
    pendingReplaceOnly = nil
    switch kind {
    case .record: requestPermissionAndRecord()
    case .importClip: presentImportPanel(sessionID: sessionID)
    }
  }

  func importClip() {
    guard !isRecording, !isAnalyzing, !isRequestingPermission else { return }
    if selectedSession?.isMimic == true, destination.isWorkspace { return }
    guard let session = selectedSession,
      !session.isMimic,
      destination.isWorkspace
    else {
      presentImportPanel(sessionID: nil)
      return
    }
    if !session.keepsRecordings {
      pendingReplaceOnly = ReplaceOnlyPrompt(sessionID: session.id, kind: .importClip)
      return
    }
    presentImportPanel(sessionID: session.id)
  }

  func startMimic() {
    guard !isRecording, !isAnalyzing, !isRequestingPermission else { return }
    navigate(to: .mimicStart)
  }

  func useCurrentRecordingAsMimicReference() {
    guard let take = selectedTake, !isRecording, !isAnalyzing else { return }
    cancelMimicPreparation()
    let id = UUID()
    mimicPreparationID = id
    mimicIsPreparing = true
    errorMessage = nil
    let sourceName: String
    if let sessionName = selectedSession?.name, !sessionName.isEmpty {
      sourceName = sessionName
    } else {
      sourceName = take.audioURL.deletingPathExtension().lastPathComponent
    }
    let staged = FileManager.default.temporaryDirectory.appendingPathComponent(
      "voice-coach-mimic-\(id).wav")
    Task {
      do {
        if FileManager.default.fileExists(atPath: staged.path) {
          try FileManager.default.removeItem(at: staged)
        }
        try FileManager.default.copyItem(at: take.audioURL, to: staged)
        guard mimicPreparationID == id else {
          try? FileManager.default.removeItem(at: staged)
          return
        }
        presentMimicDraft(id: id, url: staged, sourceName: sourceName, source: take.takeSource)
        destination = .mimicStart
      } catch {
        try? FileManager.default.removeItem(at: staged)
        if mimicPreparationID == id {
          mimicIsPreparing = false
          mimicPreparationID = nil
          errorMessage =
            "Could not use this recording as a Mimic reference. \(error.localizedDescription)"
        }
      }
    }
  }

  private func presentImportPanel(sessionID: UUID?) {
    let panel = NSOpenPanel()
    panel.title = "Import an audio or video clip"
    panel.message = "Voice Coach will extract the audio and save an analyzed copy on this Mac."
    panel.prompt = "Import clip"
    panel.allowedContentTypes = AudioImportService.allowedContentTypes
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

    let targetID: UUID
    if let sessionID {
      targetID = sessionID
      selectedSessionID = sessionID
      pendingCaptureIsNewSession = false
    } else {
      prepareStandaloneCapture()
      guard let pending = selectedSessionID else { return }
      targetID = pending
      pendingImportSourceURL = sourceURL
    }

    let takeID = UUID()
    let source = AudioImportService.source(for: sourceURL)
    do {
      let destinationURL = try store.importedAudioURL(
        sessionID: targetID,
        takeID: takeID,
        fileExtension: "wav"
      )
      isAnalyzing = true
      errorMessage = nil
      toastMessage = nil
      transcriptionNotice = nil

      Task {
        do {
          try await AudioImportService.prepareAudio(from: sourceURL, to: destinationURL)
          analyze(url: destinationURL, takeID: takeID, source: source)
        } catch {
          try? FileManager.default.removeItem(at: destinationURL)
          discardPendingStandaloneIfEmpty()
          errorMessage = "Import failed: \(error.localizedDescription)"
          isAnalyzing = false
        }
      }
    } catch {
      discardPendingStandaloneIfEmpty()
      errorMessage =
        "Voice Coach could not create local storage for this import. \(error.localizedDescription)"
    }
  }
}
