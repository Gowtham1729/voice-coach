extension AppModel {
  var hasUnsavedAudio: Bool {
    isRecording || isCapturingMimicReference || hasMenuBarReference || mimicDraft != nil
      || pendingMimicAudio != nil || pendingMimicTake != nil || mimicPhase != .ready
  }

  var canStartQuickPractice: Bool {
    !isRecording && !isCapturingMimicReference && !isAnalyzing && !isRequestingPermission
      && !mimicIsPreparing && mimicDraft == nil && !hasMenuBarReference
      && mimicPhase == .ready && !hasPendingMimicWork && pendingReplaceOnly == nil
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
    destination = .mimicStart
  }

  func discardMenuBarReference() {
    guard hasMenuBarReference else { return }
    cancelMimicPreparation()
    if destination == .mimicStart { destination = .home }
  }
}
