import AVFoundation
import Foundation
import Testing
import VoiceCoachCore
import VoiceCoachSession

@testable import VoiceCoachApp

@Suite("Suggested practice creation")
@MainActor
struct SuggestedPracticeCreationTests {
  @Test(
    "One or multiple clips save independent references and keep the original", arguments: [1, 2])
  func createsBatch(count: Int) async throws {
    let (model, root, take) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let originalBytes = try Data(contentsOf: take.audioURL)
    let clips = Array(model.suggestedPracticeClips.prefix(count))
    let draftID = try #require(model.mimicDraft?.id)
    let task = try #require(
      model.createPracticeSessions(
        draftID: draftID,
        selections: clips.map(PracticeClipSelection.init)))
    // Repeated clicks cannot start a second batch.
    #expect(
      model.createPracticeSessions(
        draftID: draftID,
        selections: [PracticeClipSelection(model.suggestedPracticeClips[0])]) == nil)
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
    let draftID = try #require(model.mimicDraft?.id)
    let task = try #require(
      model.createPracticeSessions(
        draftID: draftID,
        selections: model.suggestedPracticeClips.map(PracticeClipSelection.init)))
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
    let draftID = try #require(model.mimicDraft?.id)
    let task = try #require(
      model.createPracticeSessions(
        draftID: draftID,
        selections: model.suggestedPracticeClips.map(PracticeClipSelection.init)))
    await task.value
    #expect(model.sessions.count == 1 && model.sessions.first?.latestTake == take)
    #expect(model.errorTitle == "Save failed")
    try expectOnlySourceFolder(model)
    #expect(FileManager.default.fileExists(atPath: take.audioURL.path))
    #expect(!model.isAnalyzing)
  }

  @Test(
    "Cancellation after staging a clip removes the batch without surfacing late failures",
    arguments: [false, true])
  func cancellation(lateFailure: Bool) async throws {
    let (model, root, take) = try fixture(
      suspendPreparation: true, failAfterCancellation: lateFailure)
    defer { try? FileManager.default.removeItem(at: root) }
    let draftID = try #require(model.mimicDraft?.id)
    let task = try #require(
      model.createPracticeSessions(
        draftID: draftID,
        selections: model.suggestedPracticeClips.map(PracticeClipSelection.init)))
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

  @Test("Stale draft or phrase selection cannot create sessions")
  func staleSelection() throws {
    let (model, root, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let draftID = try #require(model.mimicDraft?.id)
    #expect(
      model.createPracticeSessions(
        draftID: UUID(), selections: [PracticeClipSelection(model.suggestedPracticeClips[0])])
        == nil)
    #expect(
      model.createPracticeSessions(draftID: draftID, selections: [])
        == nil)
    #expect(
      model.createPracticeSessions(
        draftID: draftID,
        selections: [
          PracticeClipSelection(phraseID: 0, start: 0, end: 1),
          PracticeClipSelection(phraseID: 999, start: 0, end: 1),
        ]) == nil)
    #expect(!model.isAnalyzing)
  }

  @Test(
    "Native WAV trimming preserves the exact source samples and survives reload",
    arguments: [16_000.0, 48_000.0])
  func nativeAudioBatch(sampleRate: Double) async throws {
    let (fixtureModel, root, take) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
    let frameCount = AVAudioFrameCount(sampleRate * 5)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
    buffer.frameLength = frameCount
    let samples = try #require(buffer.floatChannelData?[0])
    for index in 0..<Int(frameCount) {
      let time = Double(index) / sampleRate
      let phase = 2 * Double.pi * (160 * time + 12 * time * time)
      samples[index] = Float(0.2 * sin(phase))
    }
    // Close the writer before the production preparation service reads the WAV.
    do {
      let file = try AVAudioFile(forWriting: take.audioURL, settings: format.settings)
      try file.write(from: buffer)
    }
    let original = try Data(contentsOf: take.audioURL)
    try original.write(to: #require(fixtureModel.mimicDraft).url)
    let model = AppModel(storageRoot: root)
    let sourceSession = try #require(fixtureModel.selectedSession)
    model.openTake(sessionID: sourceSession.id, takeID: take.id)
    model.mimicDraft = fixtureModel.mimicDraft
    model.mimicPreparationID = fixtureModel.mimicPreparationID
    model.destination = .mimicStart
    let clips = model.suggestedPracticeClips
    let draftID = try #require(model.mimicDraft?.id)
    let task = try #require(
      model.createPracticeSessions(
        draftID: draftID,
        selections: clips.map(PracticeClipSelection.init)))
    await task.value
    #expect(model.errorMessage == nil)
    let reloaded = AppModel(storageRoot: root)
    let practices = reloaded.sessions.filter(\.isMimic)
    #expect(practices.count == clips.count)
    #expect(try Data(contentsOf: take.audioURL) == original)
    for clip in clips {
      let session = try #require(practices.first { $0.mimicReference?.sourceStart == clip.start })
      let reference = try #require(session.mimicReference)
      let file = try AVAudioFile(forReading: reference.take.audioURL)
      let first = Int((clip.start * sampleRate).rounded())
      let last = Int((clip.end * sampleRate).rounded())
      #expect(file.processingFormat.sampleRate == sampleRate)
      #expect(file.length == Int64(last - first))
      let trimmed = try #require(
        AVAudioPCMBuffer(
          pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
      try file.read(into: trimmed)
      let actual = try #require(trimmed.floatChannelData?[0])
      #expect((0..<Int(trimmed.frameLength)).allSatisfy { actual[$0] == samples[first + $0] })
      #expect(reference.take.transcription == clip.transcription)
      #expect(
        abs(reference.take.result.metrics.duration - Double(file.length) / sampleRate) < 0.00001)
      #expect(
        reference.take.transcription?.words.allSatisfy {
          $0.start >= 0 && $0.end <= reference.take.result.metrics.duration + 1 / sampleRate
        } == true)
    }
  }

  @Test("Phrases are prepared in a draft before any practice is saved")
  func prepareDraft() async throws {
    let transcript = TranscriptionResult(
      text: "A phrase.",
      words: [
        TranscriptWord(word: "A", start: 0.2, end: 0.8),
        TranscriptWord(word: "phrase.", start: 0.9, end: 1.7),
      ], localeIdentifier: "en_GB", engine: .system)
    let (model, root, _) = try fixture(transcriptionOutcome: transcript)
    defer { try? FileManager.default.removeItem(at: root) }
    model.cancelMimicPreparation()
    let input = root.appendingPathComponent("import.wav")
    try writePlayableAudio(to: input)
    let id = UUID()
    model.mimicPreparationID = id
    await model.presentMimicDraft(
      id: id, url: input, sourceName: "Imported clip", source: .importedAudio
    ).value
    #expect(model.mimicDraft?.transcription == transcript)
    #expect(model.suggestedPracticeClips.count == 1)
    #expect(try model.store.load().count == 1)
    #expect(!model.mimicIsPreparing && !model.mimicIsFindingPhrases)
    #expect(FileManager.default.fileExists(atPath: input.path))
  }

  @Test("An imported draft creates practices without saving a source recording")
  func unsavedDraft() async throws {
    let (model, root, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    model.sessions = []
    #expect(model.persist())
    let id = try #require(model.mimicDraft?.id)
    let task = try #require(
      model.createPracticeSessions(
        draftID: id, selections: model.suggestedPracticeClips.map(PracticeClipSelection.init)))
    await task.value
    let saved = try model.store.load()
    #expect(saved.count == 2 && saved.allSatisfy(\.isMimic))
    #expect(model.mimicDraft == nil)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("draft.wav").path))
  }

  @Test("Dismissing a batch cannot clear a replacement draft's preparation state")
  func replacedDraftAfterCancellation() async throws {
    let (model, root, _) = try fixture(suspendPreparation: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let id = try #require(model.mimicDraft?.id)
    let task = try #require(
      model.createPracticeSessions(
        draftID: id, selections: model.suggestedPracticeClips.map(PracticeClipSelection.init)))
    while model.practiceClipCreationProgress != nil {
      let folders = try FileManager.default.contentsOfDirectory(
        at: root.appendingPathComponent("Sessions"), includingPropertiesForKeys: nil)
      if folders.count > 1 { break }
      await Task.yield()
    }
    model.cancelMimicPreparation()
    let replacementID = UUID()
    model.mimicPreparationID = replacementID
    model.mimicIsPreparing = true
    await task.value
    #expect(model.mimicPreparationID == replacementID && model.mimicIsPreparing)
    #expect(try model.store.load().count == 1)
    try expectOnlySourceFolder(model)
  }

  @Test(
    "Manual selection uses the excerpt transcript and rejects empty recognition",
    arguments: [false, true])
  func manualExcerpt(emptyRecognition: Bool) async throws {
    let transcript = TranscriptionResult(
      text: emptyRecognition ? "" : "Manually chosen phrase.", words: [],
      localeIdentifier: "en_GB", engine: .system)
    let (model, root, take) = try fixture(transcriptionOutcome: transcript)
    defer { try? FileManager.default.removeItem(at: root) }
    let draftID = try #require(model.mimicDraft?.id)
    let task = try #require(
      model.createPracticeSessions(
        draftID: draftID,
        selections: [PracticeClipSelection(phraseID: nil, start: 1, end: 3)]))
    await task.value
    if emptyRecognition {
      try expectOriginalOnly(model, take: take)
      #expect(model.errorMessage != nil)
    } else {
      let reference = try #require(model.store.load().first(where: \.isMimic)?.mimicReference)
      #expect(reference.sourceStart == 1 && reference.sourceEnd == 3)
      #expect(reference.take.transcription == transcript)
      #expect(model.errorMessage == nil && model.mimicDraft == nil)
    }
  }

  @Test("Unavailable recognition keeps the manual draft and valid audio can save")
  func unavailableRecognition() async throws {
    let (model, root, _) = try fixture(transcriptionError: .runtimeUnavailable)
    defer { try? FileManager.default.removeItem(at: root) }
    model.cancelMimicPreparation()
    let input = root.appendingPathComponent("import.wav")
    try writePlayableAudio(to: input)
    let id = UUID()
    model.mimicPreparationID = id
    await model.presentMimicDraft(
      id: id, url: input, sourceName: "Imported clip", source: .importedAudio
    ).value
    #expect(model.mimicDraft != nil && model.suggestedPracticeClips.isEmpty)
    #expect(!model.mimicIsPreparing && !model.mimicIsFindingPhrases)
    let task = try #require(
      model.createPracticeSessions(
        draftID: id, selections: [PracticeClipSelection(phraseID: nil, start: 0, end: 2)]))
    await task.value
    #expect(try model.store.load().filter(\.isMimic).count == 1)
    #expect(model.transcriptionNotice != nil && model.errorMessage == nil)
  }

  @Test("Adjusted phrases use edited audio bounds and a fresh transcript within the batch")
  func adjustedBatch() async throws {
    let fresh = TranscriptionResult(
      text: "Adjusted phrase.",
      words: [
        TranscriptWord(word: "Adjusted", start: 0.1, end: 0.6),
        TranscriptWord(word: "phrase.", start: 0.7, end: 1.1),
      ], localeIdentifier: "en_GB", engine: .system)
    let (model, root, _) = try fixture(transcriptionOutcome: fresh)
    defer { try? FileManager.default.removeItem(at: root) }
    let clips = model.suggestedPracticeClips
    let draftID = try #require(model.mimicDraft?.id)
    let task = try #require(
      model.createPracticeSessions(
        draftID: draftID,
        selections: [
          PracticeClipSelection(phraseID: clips[0].id, start: 0.3, end: 1.6),
          PracticeClipSelection(phraseID: clips[1].id, start: clips[1].start, end: clips[1].end),
        ]))
    await task.value
    let practices = try model.store.load().filter(\.isMimic)
    #expect(practices.count == 2)
    let edited = try #require(
      practices.first { $0.mimicReference?.sourceStart == 0.3 }?.mimicReference)
    #expect(edited.sourceEnd == 1.6 && edited.take.transcription == fresh)
    #expect(abs(edited.take.result.metrics.duration - 1.3) < 0.001)
    let unchanged = try #require(
      practices.first { $0.mimicReference?.sourceStart == clips[1].start })
    #expect(unchanged.mimicReference?.take.transcription == clips[1].transcription)
  }

  @Test("Invalid edited ranges and duplicate choices cannot stage a batch")
  func invalidEditedRanges() throws {
    let (model, root, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let id = (try #require(model.mimicDraft)).id
    for range in [(-1.0, 2.0), (0.0, 6.0), (1.0, 1.5), (Double.nan, 2.0)] {
      #expect(
        model.createPracticeSessions(
          draftID: id,
          selections: [
            PracticeClipSelection(phraseID: 0, start: range.0, end: range.1)
          ]) == nil)
    }
    let same = PracticeClipSelection(phraseID: 0, start: 0.1, end: 1.8)
    #expect(model.createPracticeSessions(draftID: id, selections: [same, same]) == nil)
    #expect(!model.isAnalyzing && model.sessions.count == 1)
  }

  private func writePlayableAudio(to url: URL) throws {
    let rate = 8_000.0
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
    let count: AVAudioFrameCount = 40_000
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count))
    buffer.frameLength = count
    let samples = try #require(buffer.floatChannelData?[0])
    for index in 0..<Int(count) {
      let phase = 2 * Double.pi * 160 * Double(index) / rate
      samples[index] = Float(0.2 * sin(phase))
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
  }

  private func fixture(
    failLaterClip: Bool = false, suspendPreparation: Bool = false,
    failAfterCancellation: Bool = false,
    transcriptionOutcome: TranscriptionResult? = nil,
    transcriptionError: TranscriptionError? = nil
  ) throws -> (AppModel, URL, PracticeSession) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("clip-tests-\(UUID())")
    let store = try SessionStore(rootURL: root)
    let sessionID = UUID()
    let url = try store.recordingURL(sessionID: sessionID, takeID: UUID())
    try Data("original audio fixture".utf8).write(to: url)
    let take = PracticeSession(
      audioURL: url, source: .importedAudio, result: analysis(duration: 5),
      transcription: TranscriptionResult(
        text: "First phrase. Second phrase.",
        words: [
          TranscriptWord(word: "First", start: 0.2, end: 0.8),
          TranscriptWord(word: "phrase.", start: 0.9, end: 1.6),
          TranscriptWord(word: "Second", start: 3, end: 3.6),
          TranscriptWord(word: "phrase.", start: 3.7, end: 4.4),
        ], localeIdentifier: "en_GB", engine: .system))
    let dependencies = AppDependencies(
      recorder: AudioRecorder(), systemAudioCapture: SystemAudioCapture(), sessionStore: store,
      sessionChatResponder: LocalSessionChatResponder(),
      transcribe: { _, _, _ in
        if let transcriptionError { throw transcriptionError }
        if let transcriptionOutcome {
          return TranscriptionOutcome(result: transcriptionOutcome, engine: .system, notice: nil)
        }
        Issue.record("Suggested clips should reuse the source transcript")
        throw TranscriptionError.noSpeechRecognized
      },
      preparePracticeClip: { _, destination, start, end in
        try Data("reference audio fixture".utf8).write(to: destination)
        if suspendPreparation {
          do { try await Task.sleep(for: .seconds(60)) } catch {
            if failAfterCancellation { throw AudioImportError.invalidExcerpt }
            throw error
          }
        }
        if failLaterClip && start > 2 { throw AudioImportError.invalidExcerpt }
        return analysis(duration: end - start)
      })
    let model = AppModel(loadPersistedData: false, dependencies: dependencies)
    model.sessions = [
      CoachingSession(
        id: sessionID, name: "Source", mode: .general, prompt: "", keepsRecordings: true,
        takes: [take])
    ]
    model.selectedSessionID = sessionID
    model.selectedTakeID = take.id
    let draftURL = root.appendingPathComponent("draft.wav")
    try Data(contentsOf: url).write(to: draftURL)
    let draftID = UUID()
    model.mimicPreparationID = draftID
    model.mimicDraft = MimicReferenceDraft(
      id: draftID, url: draftURL, sourceName: "Source", duration: 5, peaks: [],
      source: .importedAudio, transcription: take.transcription,
      transcriptionLocaleIdentifier: "en_GB")
    model.destination = .mimicStart
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
  let sampleRate = 8_000.0
  let frameCount = Int(duration * sampleRate)
  let samples: [Float] = (0..<frameCount).map { index -> Float in
    let time = Double(index) / sampleRate
    let phase = 2 * Double.pi * 160 * time
    return Float(0.2 * sin(phase))
  }
  return AudioAnalyzer().analyze(samples: samples, sampleRate: sampleRate)
}
