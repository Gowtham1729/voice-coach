import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  func navigate(to destination: AppDestination) {
    if isRecording || isAnalyzing || mimicPhase != .ready { return }
    stopPlayback()
    self.destination = destination
  }

  func navigate(toSection section: NavigationSection) {
    switch section {
    case .home: navigate(to: .home)
    case .library: navigate(to: .library)
    case .mimics: navigate(to: .mimics)
    }
  }

  /// Immediate capture from Home. Does not create a library item until a valid recording is saved.
  func startHomeRecording() {
    if isRecording {
      stopRecording()
      return
    }
    guard !isAnalyzing, !isRequestingPermission, !isCapturingMimicReference else { return }
    discardPendingStandaloneIfEmpty()
    selectedTakeID = nil
    destination = .home
    prepareStandaloneCapture()
    requestPermissionAndRecord()
  }

  func resumeSession(_ id: UUID) {
    guard let session = sessions.first(where: { $0.id == id }) else { return }
    if session.isMimic {
      selectedSessionID = id
      selectedTakeID = session.latestTake?.id
      lastUsedMimicID = id
      mimicWorkspaceMode = session.latestTake != nil ? .compare : .practice
      navigate(to: .practice(id))
    } else if let latest = session.latestTake {
      openTake(sessionID: id, takeID: latest.id)
    } else {
      selectedSessionID = nil
      selectedTakeID = nil
      navigate(to: .library)
    }
  }

  func openTake(sessionID: UUID, takeID: UUID? = nil) {
    guard let session = sessions.first(where: { $0.id == sessionID }),
      let take = takeID.flatMap({ id in session.takes.first(where: { $0.id == id }) })
        ?? session.latestTake
    else { return }
    selectedSessionID = sessionID
    selectedTakeID = take.id
    if session.isMimic {
      lastUsedMimicID = sessionID
      setMimicWorkspaceMode(.compare)
      navigate(to: .practice(sessionID))
    } else {
      navigate(to: .take(sessionID, take.id))
    }
  }

  func selectTake(_ takeID: UUID) {
    guard let selectedSession, selectedSession.takes.contains(where: { $0.id == takeID }) else {
      return
    }
    stopPlayback()
    selectedTakeID = takeID
    if selectedSession.mode == .mimic, mimicWorkspaceMode == .practice {
      mimicWorkspaceMode = .compare
    }
    mimicSelectedWord = nil
    if case .take(let sessionID, _) = destination { destination = .take(sessionID, takeID) }
  }

  /// Switch Mimic Practice / Compare / Analysis while keeping take selection coherent.
  func setMimicWorkspaceMode(_ mode: MimicWorkspaceMode) {
    stopPlayback()
    if mode != .practice, selectedTakeID == nil {
      selectedTakeID = selectedSession?.latestTake?.id
    }
    mimicWorkspaceMode = mode
  }

  func renameSession(_ id: UUID, to name: String) {
    guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanName.isEmpty else { return }
    sessions[index].name = cleanName
    if sessions[index].mode == .mimic {
      sessions[index].mimicReference?.sourceName = cleanName
    }
    sessions[index].updatedAt = Date()
    sortSessions()
    persist()
  }

  func deleteSession(_ id: UUID) {
    if pendingMimicSessionID == id {
      errorMessage =
        "This Mimic has an unsaved recording. Retry saving it or reveal the audio file before deleting."
      return
    }
    stopPlayback()
    guard let session = sessions.first(where: { $0.id == id }) else { return }
    let previousSessions = sessions
    let previousSessionID = selectedSessionID
    let previousTakeID = selectedTakeID
    let previousDestination = destination
    let wasMimic = session.isMimic
    let attemptCount = session.takeCount
    sessions.removeAll { $0.id == id }
    if lastUsedMimicID == id { lastUsedMimicID = nil }
    if selectedSessionID == id {
      selectedSessionID = nil
      selectedTakeID = nil
      destination = wasMimic ? .mimics : .library
    }
    guard persist() else {
      sessions = previousSessions
      selectedSessionID = previousSessionID
      selectedTakeID = previousTakeID
      destination = previousDestination
      return
    }
    do {
      try store.deleteSessionData(sessionID: id)
      toastMessage = deleteMessage(wasMimic: wasMimic, attemptCount: attemptCount)
    } catch {
      errorMessage =
        "Removed from the library, but the recording folder could not be deleted. \(error.localizedDescription)"
    }
  }

  private func deleteMessage(wasMimic: Bool, attemptCount: Int) -> String {
    guard wasMimic else { return "Recording group removed" }
    guard attemptCount > 0 else { return "Mimic reference removed" }
    let noun = attemptCount == 1 ? "attempt" : "attempts"
    return "Mimic, reference, and \(attemptCount) \(noun) removed"
  }

  func archiveMimic(_ id: UUID, archived: Bool = true) {
    guard let index = sessions.firstIndex(where: { $0.id == id && $0.isMimic }) else { return }
    sessions[index].archived = archived
    sessions[index].updatedAt = Date()
    if archived, lastUsedMimicID == id { lastUsedMimicID = nil }
    persist()
    if archived, selectedSessionID == id {
      selectedSessionID = nil
      selectedTakeID = nil
      destination = .mimics
    }
    toastMessage = archived ? "Mimic archived" : "Mimic restored"
  }

  func cleanupEmptyLegacySessions() {
    let emptyIDs = sessions.filter(\.isEmptyLegacy).map(\.id)
    guard !emptyIDs.isEmpty else {
      toastMessage = "No unused folders to clean up"
      return
    }
    sessions.removeAll { emptyIDs.contains($0.id) }
    guard persist() else { return }
    for id in emptyIDs {
      try? store.deleteSessionData(sessionID: id)
    }
    if emptyIDs.count == 1 {
      toastMessage = "Removed 1 unused folder"
    } else {
      toastMessage = "Removed \(emptyIDs.count) unused folders"
    }
  }

  func deleteTake(_ takeID: UUID) {
    stopPlayback()
    guard let sessionID = selectedSessionID,
      let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
      let takeIndex = sessions[sessionIndex].takes.firstIndex(where: { $0.id == takeID })
    else { return }

    let previousSessions = sessions
    let previousTakeID = selectedTakeID
    let previousDestination = destination
    let removed = sessions[sessionIndex].takes.remove(at: takeIndex)
    sessions[sessionIndex].mimicAttemptStyles?.removeValue(forKey: takeID)
    let remainingCount = sessions[sessionIndex].takes.count
    sessions[sessionIndex].updatedAt = Date()

    if selectedTakeID == takeID {
      let remaining = sessions[sessionIndex].takes
      selectedTakeID =
        remaining.indices.contains(takeIndex) ? remaining[takeIndex].id : remaining.last?.id
      if case .take = destination {
        if let selectedTakeID {
          destination = .take(sessionID, selectedTakeID)
        } else {
          selectedSessionID = nil
          destination = .library
        }
      }
    }

    sortSessions()
    guard persist() else {
      sessions = previousSessions
      selectedTakeID = previousTakeID
      destination = previousDestination
      return
    }

    try? store.deleteTakeAnalysis(sessionID: sessionID, takeID: takeID)
    try? FileManager.default.removeItem(at: removed.audioURL)
    if reportCache?.takeID == takeID { reportCache = nil }
    if remainingCount == 0 { mimicWorkspaceMode = .practice }
    toastMessage = "Recording removed"
  }
}
