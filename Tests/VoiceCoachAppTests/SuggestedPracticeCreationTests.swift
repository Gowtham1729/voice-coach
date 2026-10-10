import Foundation
import Testing
import VoiceCoachCore
import VoiceCoachSession

@testable import VoiceCoachApp

@Suite("Suggested practice creation")
@MainActor
struct SuggestedPracticeCreationTests {
  @Test("One or multiple clips save independent references and keep the original", arguments: [1, 2])
  func createsBatch(count: Int) async throws {
    let (model, root, take) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let originalBytes = try Data(contentsOf: take.audioURL)
    let clips = Array(model.suggestedPracticeClips(for: take).prefix(count))
    let task = try #require(model.createSuggestedPracticeSessions(
      takeID: take.id, clipIDs: Set(clips.map(\.id))))
    // Repeated clicks cannot start a second batch.
    #expect(model.createSuggestedPracticeSessions(takeID: take.id, clipIDs: [0]) == nil)
    await task.value

    let saved = try model.store.load()
    let practices = saved.filter(\.isMimic)
    #expect(practices.count == count)
    #expect(saved.first(where: { !$0.isMimic })?.latestTake == take)
    #expect(try Data(contentsOf: take.audioURL) == originalBytes)
    for clip in clips {
      let session = try #require(practices.first { $0.mimicReference?.sourceStart == clip.start })
      let reference = try #require(session.mimicReference)
      #expect(reference.sourceEnd == clip.end)
      #expect(reference.take.transcription == clip.transcription)
      #expect(reference.take.audioURL != take.audioURL)
      #expect(abs(reference.take.result.metrics.duration - clip.duration) < 0.0002)
      #expect(FileManager.default.fileExists(atPath: reference.take.audioURL.path))
      #expect(!reference.take.words.isEmpty)
      #expect(session.keepsRecordings && session.mimicStyle == .listenAndRepeat)
      #expect(session.transcriptionLocaleIdentifier == "en_GB")
    }
    #expect(!model.isAnalyzing && model.practiceClipCreationProgress == nil)
    #expect(model.errorMessage == nil)
    if count == 1 {
      #expect(model.selectedSession?.isMimic == true)
      #expect(model.mimicWorkspaceMode == .practice)
    } else {
      #expect(model.destination == .mimics)
    }
  }

  @Test("A failure in a later clip rolls back every new folder")
  func preparationFailure() async throws {
    let (model, root, take) = try fixture(failLaterClip: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let task = try #require(model.createSuggestedPracticeSessions(takeID: take.id, clipIDs: [0, 2]))
    await task.value
    try expectOriginalOnly(model, take: take)
    #expect(model.errorMessage != nil)
  }

  @Test("Save failure leaves the source and no new reference folders")
  func saveFailure() async throws {
    let (model, root, take) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    // Fail the atomic index replacement after the references have been prepared.
    let library = root.appendingPathComponent("session-library.json")
    try FileManager.default.removeItem(at: library)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: false)
    let task = try #require(model.createSuggestedPracticeSessions(takeID: take.id, clipIDs: [0, 2]))
    await task.value
    #expect(model.sessions.count == 1 && model.sessions.first?.latestTake == take)
    #expect(model.errorTitle == "Save failed")
    try expectOnlySourceFolder(model)
    #expect(FileManager.default.fileExists(atPath: take.audioURL.path))
    #expect(!model.isAnalyzing)
  }

  @Test("Cancellation after staging a clip removes the batch")
  func cancellation() async throws {
    let (model, root, take) = try fixture(suspendPreparation: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let task = try #require(model.createSuggestedPracticeSessions(takeID: take.id, clipIDs: [0, 2]))
    // The injected preparation writes a staged file before suspending.
    while model.practiceClipCreationProgress != nil {
      let folders = try FileManager.default.contentsOfDirectory(
        at: root.appendingPathComponent("Sessions"), includingPropertiesForKeys: nil)
      if folders.count > 1 { break }
      await Task.yield()
    }
    model.cancelSuggestedPracticeCreation()
    await task.value
    try expectOriginalOnly(model, take: take)
    #expect(model.errorMessage == nil)
  }

  @Test("Stale take or clip selection cannot create sessions")
  func staleSelection() throws {
    let (model, root, take) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(model.createSuggestedPracticeSessions(takeID: UUID(), clipIDs: [0]) == nil)
    #expect(model.createSuggestedPracticeSessions(takeID: take.id, clipIDs: []) == nil)
    #expect(model.createSuggestedPracticeSessions(takeID: take.id, clipIDs: [0, 999]) == nil)
    #expect(!model.isAnalyzing)
  }

  private func fixture(
    failLaterClip: Bool = false, suspendPreparation: Bool = false
  ) throws -> (AppModel, URL, PracticeSession) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("clip-tests-\(UUID())")
    let store = try SessionStore(rootURL: root)
    let sessionID = UUID()
    let url = try store.recordingURL(sessionID: sessionID, takeID: UUID())
    try Data("original audio fixture".utf8).write(to: url)
    let take = PracticeSession(
      audioURL: url, source: .importedAudio, result: analysis(duration: 5),
      transcription: TranscriptionResult(text: "First phrase. Second phrase.", words: [
        TranscriptWord(word: "First", start: 0.2, end: 0.8),
        TranscriptWord(word: "phrase.", start: 0.9, end: 1.6),
        TranscriptWord(word: "Second", start: 3, end: 3.6),
        TranscriptWord(word: "phrase.", start: 3.7, end: 4.4),
      ], localeIdentifier: "en_GB", engine: .system))
    let dependencies = AppDependencies(
      recorder: AudioRecorder(), systemAudioCapture: SystemAudioCapture(), sessionStore: store,
      sessionChatResponder: LocalSessionChatResponder(),
      transcribe: { _, _, _ in
        Issue.record("Suggested clips should reuse the source transcript")
        throw TranscriptionError.noSpeechRecognized
      },
      preparePracticeClip: { _, destination, start, end in
        try Data("reference audio fixture".utf8).write(to: destination)
        if suspendPreparation { try await Task.sleep(for: .seconds(60)) }
        if failLaterClip && start > 2 { throw AudioImportError.invalidExcerpt }
        return analysis(duration: end - start)
      })
    let model = AppModel(loadPersistedData: false, dependencies: dependencies)
    model.sessions = [CoachingSession(
      id: sessionID, name: "Source", mode: .general, prompt: "", keepsRecordings: true, takes: [take])]
    model.selectedSessionID = sessionID
    model.selectedTakeID = take.id
    model.destination = .take(sessionID, take.id)
    #expect(model.persist(analysisTakeIDs: [take.id]))
    return (model, root, take)
  }

  private func expectOriginalOnly(_ model: AppModel, take: PracticeSession) throws {
    #expect(model.sessions.count == 1 && model.sessions.first?.latestTake == take)
    #expect(try model.store.load().count == 1)
    #expect(FileManager.default.fileExists(atPath: take.audioURL.path))
    #expect(!model.isAnalyzing && model.practiceClipCreationProgress == nil)
    try expectOnlySourceFolder(model)
  }

  private func expectOnlySourceFolder(_ model: AppModel) throws {
    let folders = try FileManager.default.contentsOfDirectory(
      at: model.store.rootURL.appendingPathComponent("Sessions"), includingPropertiesForKeys: nil)
    #expect(folders.count == 1)
  }
}

private func analysis(duration: Double) -> AnalysisResult {
  let samples = (0..<Int(duration * 8_000)).map {
    Float(0.2 * sin(2 * .pi * 160 * Double($0) / 8_000))
  }
  return AudioAnalyzer().analyze(samples: samples, sampleRate: 8_000)
}
