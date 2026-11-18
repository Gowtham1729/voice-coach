import Foundation

extension AppModel {
  /// Real audio that quitting would lose. Playback, count-in, and a permission wait hold none.
  var hasUnsavedAudio: Bool {
    isRecording || isCapturingMimicReference || (hasMenuBarReference && !isRequestingPermission)
      || mimicDraft != nil || pendingMimicAudio != nil || pendingMimicTake != nil
  }

  /// Work that quitting would interrupt even though no audio is waiting to be saved.
  var isPreparingAudio: Bool { isAnalyzing || mimicIsPreparing }

  var canStartQuickPractice: Bool {
    !isRecording && !isCapturingMimicReference && !isAnalyzing && !isRequestingPermission
      && !mimicIsPreparing && !mimicIsFindingPhrases && practiceClipCreationProgress == nil
      && mimicDraft == nil && !hasMenuBarReference
      && mimicPhase == .ready && !hasPendingMimicWork && pendingReplaceOnly == nil
      && destination != .mimicStart
  }

  /// A finished menu bar clip is waiting and no sheet is showing it.
  var hasMenuBarClipAwaitingReview: Bool {
    hasMenuBarReference && mimicDraft != nil && !mimicIsPreparing && !isCapturingMimicReference
      && destination != .mimicStart
  }

  /// Reuses the reference-capture service without opening a sheet over the source app.
  func startMenuBarReferenceCapture() {
    guard canStartQuickPractice else { return }
    captureMimicReferencePressed(fromMenuBar: true)
  }

  /// Stop first, then hand the same staged clip to the existing trim-and-practice sheet.
  func reviewMenuBarReference() {
    guard hasMenuBarReference, !isRequestingPermission else { return }
    if isCapturingMimicReference { finishMimicReferenceCapture() }
    guard hasMenuBarReference else { return }
    stopPlayback()
    destination = .mimicStart
  }

  func discardMenuBarReference() {
    guard hasMenuBarReference else { return }
    cancelMimicPreparation()
    returnFromCreateSheet()
  }

  /// Dismissing the sheet cancels a phrase search or batch it started. A capture in
  /// progress or a finished menu bar clip belongs to the menu, not to a sheet that
  /// was not showing it, so a late disappearance leaves it alone.
  func mimicSheetDidDisappear() {
    guard destination != .mimicStart else { return }
    if practiceClipCreationProgress == nil, hasMenuBarReference { return }
    cancelMimicPreparation()
  }

  /// Quit cleanup: cancel preparation and capture, then remove audio that was never saved.
  func discardInFlightWorkForQuit() {
    cancelMimicPreparation()
    mimicCountInTask?.cancel()
    recorder.stop()
    timer?.invalidate()
    if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
    discardPendingStandaloneIfEmpty()
  }
}
