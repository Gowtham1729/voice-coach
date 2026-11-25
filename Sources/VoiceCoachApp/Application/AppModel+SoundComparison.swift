import Foundation
import VoiceCoachCore
import VoiceCoachSession

/// What Review can show about sounds for one take (UI in PR 3).
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
  /// The engine whose results Review shows (D6, FR-25).
  var activeSoundEngineID: String? {
    SoundComparisonEnginePreference.active(among: soundEngines)
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
