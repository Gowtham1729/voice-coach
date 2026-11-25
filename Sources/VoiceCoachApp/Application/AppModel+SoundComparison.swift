import AppKit
import Foundation
import VoiceCoachCore
import VoiceCoachSession

/// What Review can show about sounds for one take.
enum SoundComparisonStatus: Equatable {
  case noEngine
  case notComparable(SoundComparisonSkipReason)
  case running
  case failed
  /// Comparable, not run yet (it starts when the take is shown).
  case pending
  case ready(SoundComparisonResult)
}

extension AppModel {
  /// The engine whose results Review shows (D6, FR-25). Only engines whose tier is shown count,
  /// so an experimental engine never runs while Experiments hides it.
  var activeSoundEngineID: String? {
    SoundComparisonEnginePreference.active(among: availableSoundEngines)
  }

  /// Installed engines of the tiers that Settings currently lists.
  var availableSoundEngines: [SoundEngineInstall] {
    let visible = Set(
      SoundEngineCatalog.visible(showsExperimental: showsExperimentalSoundEngines).map(\.id))
    return soundEngines.filter { visible.contains($0.id) }
  }

  func setShowsExperimentalSoundEngines(_ shows: Bool) {
    guard shows != showsExperimentalSoundEngines else { return }
    SoundEngineVisibilityPreference.save(shows)
    showsExperimentalSoundEngines = shows
    if shows { refreshSoundEngines() }
  }

  /// Rows for the Sounds section of Compare, strongest first (UX-2).
  func soundFlagRows(
    for take: PracticeSession, in session: CoachingSession, result: SoundComparisonResult
  ) -> [SoundFlagRow] {
    guard let reference = session.mimicReference?.take else { return [] }
    return SoundFlagRows.make(
      result: result, reference: reference, attempt: take,
      comparison: MimicComparison.compare(reference: reference, attempt: take))
  }

  /// Plays the Reference word, the take's word, then the Reference word again (FR-17).
  /// Choosing it again while it plays stops it.
  func listenToSoundFlag(_ row: SoundFlagRow) {
    if soundListenWordIndex == row.referenceWordIndex {
      stopPlayback()
      return
    }
    guard !isRecording, !isAnalyzing, mimicPhase == .ready,
      let reference = selectedSession?.mimicReference?.take, let take = selectedTake
    else { return }
    let sequence = SoundFlagRows.listenSequence(
      for: row, referenceDuration: reference.result.metrics.duration,
      takeDuration: take.result.metrics.duration)
    guard !sequence.isEmpty else { return }
    stopPlayback()
    soundListenQueue = sequence
    soundListenWordIndex = row.referenceWordIndex
    playNextSoundListenSegment()
  }

  /// Called when a segment ends. True when the Listen sequence goes on after a short gap.
  func continueSoundListen() -> Bool {
    guard !soundListenQueue.isEmpty else {
      soundListenWordIndex = nil
      return false
    }
    soundListenTask?.cancel()
    soundListenTask = Task { [weak self] in
      try? await Task.sleep(for: SoundFlagRows.listenGap)
      guard let self, !Task.isCancelled else { return }
      self.playNextSoundListenSegment()
    }
    return true
  }

  func cancelSoundListen() {
    soundListenTask?.cancel()
    soundListenTask = nil
    soundListenQueue = []
    if soundListenWordIndex != nil { soundListenWordIndex = nil }
  }

  private func playNextSoundListenSegment() {
    guard !soundListenQueue.isEmpty, !isRecording,
      let reference = selectedSession?.mimicReference?.take, let take = selectedTake
    else {
      cancelSoundListen()
      return
    }
    let segment = soundListenQueue.removeFirst()
    let url = segment.source == .reference ? reference.audioURL : take.audioURL
    playMimicSegment(
      url: url, source: segment.source, start: segment.range.lowerBound,
      end: segment.range.upperBound, continuesSoundListen: true)
  }

  /// Deletes an engine from Settings (FR-27) and says what happened.
  func removeSoundEngine(_ engineID: String) {
    let name = SoundEngineCatalog.descriptor(engineID)?.name ?? engineID
    Task {
      do {
        try await deleteSoundEngine(engineID)
        toastMessage = "Deleted the \(name) engine and its sound results."
      } catch {
        presentError(
          title: "Couldn’t delete the \(name) engine",
          message: "Some of its files may still be on this Mac. Try again, or remove them in Finder.")
      }
    }
  }

  func revealSoundComparisonFolder() {
    let root = LocalSoundComparisonService.defaultRoot
    let target = FileManager.default.fileExists(atPath: root.path)
      ? root : root.deletingLastPathComponent()
    NSWorkspace.shared.activateFileViewerSelecting([target])
  }

  func setActiveSoundEngine(_ id: String) {
    SoundComparisonEnginePreference.save(id)
    objectWillChange.send()
    scheduleSoundComparison()
  }

  @discardableResult
  func refreshSoundEngines() -> Task<Void, Never> {
    Task {
      soundEngines = await soundComparison.installedEngines()
      compareSoundsIfNeeded()
    }
  }

  func soundComparisonStatus(sessionID: UUID, takeID: UUID) -> SoundComparisonStatus {
    guard let engineID = activeSoundEngineID else { return .noEngine }
    guard let session = sessions.first(where: { $0.id == sessionID }),
      let take = session.takes.first(where: { $0.id == takeID })
    else { return .pending }
    if let reason = SoundComparisonSkipReason.check(
      reference: session.mimicReference?.take, attempt: take,
      localeIdentifier: session.transcriptionLocaleIdentifier)
    {
      return .notComparable(reason)
    }
    if let result = take.sounds?.comparison(
      engineID: engineID, engineVersion: SoundComparisonConfiguration.engineVersion)
    {
      return .ready(result)
    }
    if soundComparisonRunning.contains(takeID) { return .running }
    return soundComparisonFailed.contains(takeID) ? .failed : .pending
  }

  /// Runs after the current save or selection change has finished.
  func scheduleSoundComparison() {
    Task { self.compareSoundsIfNeeded() }
  }

  /// Compares the shown take with its Reference when it has no result from the active engine
  /// (FR-4, FR-5). Runs after the take is saved; a failure is only remembered, never shown as an
  /// error, and never touches the take (FR-12). The Reference is analysed once per engine and
  /// kept in its analysis file (FR-11).
  @discardableResult
  func compareSoundsIfNeeded() -> Task<Void, Never>? {
    guard let engineID = activeSoundEngineID, let session = selectedSession,
      let take = selectedTake, let reference = session.mimicReference?.take,
      case .pending = soundComparisonStatus(sessionID: session.id, takeID: take.id)
    else { return nil }
    let version = SoundComparisonConfiguration.engineVersion
    let words = (reference.transcription?.words ?? []).map(SoundWord.init)
    let cached = reference.sounds?.referenceAnalysis(
      engineID: engineID, engineVersion: version, words: words)
    let service = soundComparison
    soundComparisonRunning.insert(take.id)
    return Task {
      defer { soundComparisonRunning.remove(take.id) }
      do {
        let analysis: ReferenceAnalysis
        if let cached {
          analysis = cached
        } else {
          analysis = try await service.analyzeReference(
            engineID: engineID, audioURL: reference.audioURL, words: words)
        }
        let result = try await service.compare(
          engineID: engineID, reference: analysis, takeAudioURL: take.audioURL)
        guard storeSoundResult(
          result, analysis: cached == nil ? analysis : nil, sessionID: session.id,
          takeID: take.id, reference: reference)
        else { throw CocoaError(.fileWriteUnknown) }
      } catch {
        soundComparisonFailed.insert(take.id)
      }
    }
  }

  /// Saves a result into the take's analysis file (and a new Reference analysis into the
  /// Reference's). Skipped when the take is gone or the Reference changed meanwhile.
  private func storeSoundResult(
    _ result: SoundComparisonResult, analysis: ReferenceAnalysis?, sessionID: UUID, takeID: UUID,
    reference: PracticeSession
  ) -> Bool {
    guard !libraryLoadFailed, let index = sessions.firstIndex(where: { $0.id == sessionID }),
      let current = sessions[index].mimicReference?.take, current.id == reference.id,
      current.transcription == reference.transcription
    else { return true }
    let previous = sessions
    var changed: Set<UUID> = []
    if sessions[index].updateSounds(takeID: takeID, { $0.comparisons[result.engineID] = result }) {
      changed.insert(takeID)
    }
    if let analysis {
      sessions[index].updateSounds(takeID: reference.id) {
        $0.referenceAnalyses[analysis.engineID] = analysis
      }
      changed.insert(reference.id)
    }
    guard !changed.isEmpty else { return true }
    do {
      try store.save(sessions, analysisTakeIDs: changed)
      return true
    } catch {
      sessions = previous
      return false
    }
  }

  /// Deletes an engine's files and every sound result it made (FR-27). Audio, transcripts and
  /// other analysis are not touched.
  func deleteSoundEngine(_ engineID: String) async throws {
    try await soundComparison.deleteEngine(engineID)
    var changed: Set<UUID> = []
    for index in sessions.indices {
      changed.formUnion(sessions[index].removeSoundResults(engineID: engineID))
    }
    if !changed.isEmpty { _ = persist(analysisTakeIDs: changed) }
    soundEngines = await soundComparison.installedEngines()
  }
}
