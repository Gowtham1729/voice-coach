import AVFoundation
import Foundation
import Testing
import VoiceCoachCore
import VoiceCoachSession

@testable import VoiceCoachApp

private let helloThereOutcome = TranscriptionOutcome(
  result: TranscriptionResult(
    text: "Hello there",
    words: [
      TranscriptWord(word: "Hello", start: 0, end: 0.4),
      TranscriptWord(word: "there", start: 0.5, end: 0.9),
    ]),
  engine: .system)

@Suite("Recording creation")
@MainActor
struct RecordingCreationTests {
  @Test("Missing audio leaves no recording or pending folder")
  func missingAudio() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    model.prepareStandaloneCapture()
    let sessionID = try #require(model.selectedSessionID)
    let takeID = UUID()
    let url = try model.store.recordingURL(sessionID: sessionID, takeID: takeID)

    await model.analyze(url: url, takeID: takeID).value

    try expectRejected(model, root: root, url: url, title: "No Audio Detected")
    #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
  }

  @Test(
    "Silent capture and imports do not create library entries",
    arguments: [TakeSource.recorded, .importedAudio, .importedVideo])
  func silentAudio(source: TakeSource) async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let (url, takeID) = try prepareAudio(model, amplitude: 0)

    await model.analyze(url: url, takeID: takeID, source: source).value

    try expectRejected(model, root: root, url: url, title: "No Audio Detected")
  }

  @Test("Empty audio files do not create library entries")
  func emptyAudio() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let (url, takeID) = try prepareAudio(model, amplitude: 0, frameCount: 0)

    await model.analyze(url: url, takeID: takeID).value

    try expectRejected(model, root: root, url: url, title: "No Audio Detected")
  }

  @Test("Zero-byte files are rejected and removed")
  func zeroByteAudio() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let (url, takeID) = try prepareAudio(model)
    try Data().write(to: url)

    await model.analyze(url: url, takeID: takeID).value

    try expectRejected(model, root: root, url: url, title: "No Audio Detected")
  }

  @Test("Successful blank transcripts are rejected", arguments: ["", " \n\t "])
  func blankTranscript(text: String) async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root) { _, _, _ in
      TranscriptionOutcome(result: TranscriptionResult(text: text, words: []), engine: .system)
    }
    let (url, takeID) = try prepareAudio(model)

    await model.analyze(url: url, takeID: takeID).value

    try expectRejected(model, root: root, url: url, title: "No Speech Recognized")
  }

  @Test("Recognizer no-speech errors block saving")
  func noSpeechError() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root) { _, _, _ in throw TranscriptionError.noSpeechRecognized }
    let (url, takeID) = try prepareAudio(model)

    await model.analyze(url: url, takeID: takeID).value

    try expectRejected(model, root: root, url: url, title: "No Speech Recognized")
  }

  @Test(
    "Technical transcription failures preserve playable audio",
    arguments: [
      TranscriptionError.runtimeUnavailable, .invalidOutput, .recognitionFailed("failed"),
    ])
  func transcriptionFailure(error: TranscriptionError) async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root) { _, _, _ in throw error }
    let (url, takeID) = try prepareAudio(model)

    await model.analyze(url: url, takeID: takeID).value

    #expect(model.sessions.count == 1)
    #expect(model.sessions.first?.takes.first?.transcription == nil)
    #expect(model.errorTitle == "Transcription failed")
    #expect(model.errorMessage?.contains("Your audio was saved.") == true)
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(try AVAudioFile(forReading: url).length > 0)
    #expect(try model.store.load().first?.takes.first?.id == takeID)
    #expect(!model.isAnalyzing)
  }

  @Test("Quiet audio with recognized text saves normally")
  func validAudio() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let (url, takeID) = try prepareAudio(model, amplitude: 0.0005)
    // Avoid deferred smart naming in this fixture.
    model.pendingImportSourceURL = URL(fileURLWithPath: "/tmp/quiet.wav")

    await model.analyze(url: url, takeID: takeID).value

    #expect(model.errorMessage == nil)
    #expect(try model.store.load().first?.takes.first?.id == takeID)
    #expect(FileManager.default.fileExists(atPath: url.path))
  }

  @Test("Saving a Mimic attempt keeps Compare when the session moves to the top")
  func mimicSaveAfterSort() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let plainID = UUID()
    let mimicID = UUID()
    model.sessions = [
      CoachingSession(
        id: plainID, name: "Newer plain", updatedAt: Date(), mode: .general,
        prompt: "", keepsRecordings: true),
      CoachingSession(
        id: mimicID, name: "Reference", updatedAt: .distantPast, mode: .mimic,
        prompt: "", keepsRecordings: true),
    ]
    model.selectedSessionID = mimicID
    model.destination = .practice(mimicID)
    let takeID = UUID()
    let url = try model.store.recordingURL(sessionID: mimicID, takeID: takeID)
    try writeAudio(to: url, amplitude: 0.3)
    let take = PracticeSession(
      id: takeID, audioURL: url, result: try AudioAnalyzer().analyze(url: url))

    let earlierTakeID = UUID()
    model.skipRetryCard(for: earlierTakeID)
    #expect(model.skippedRetryCardTakeIDs.count == 1)
    model.showRetryCard(for: earlierTakeID)
    #expect(model.skippedRetryCardTakeIDs.isEmpty)
    model.skipRetryCard(for: earlierTakeID)

    model.append(take, toSessionID: mimicID)

    #expect(model.sessions.first?.id == mimicID)
    #expect(model.selectedTakeID == takeID)
    #expect(model.destination == .practice(mimicID))
    #expect(model.skippedRetryCardTakeIDs == [earlierTakeID])
    #expect(try model.store.load().first?.takes.first?.id == takeID)
  }

  @Test("Cancelling a retry before capture clears its pinned target")
  func cancelledRetryDoesNotPinLaterCapture() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let target = TargetFocus(
      referenceWordIndex: 4, word: "important", kind: .pitch, gap: 6,
      referenceRange: 1.9...2.15, takeRange: 2.0...2.25)
    model.pendingRetryTarget = (UUID(), .listenAndRepeat, target)
    model.mimicPhase = .countIn(2)
    model.cancelMimicCountIn()
    #expect(model.pendingRetryTarget == nil)

    model.pendingRetryTarget = (UUID(), .listenAndRepeat, target)
    model.mimicPhase = .playingReference
    model.mimicShouldRecordAfterPlayback = true
    model.stopPlayback()
    #expect(model.pendingRetryTarget == nil)
  }

  @Test("Changing the selection clears a pending retry target")
  func selectionChangeClearsRetryTarget() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let target = retargetFixture(word: "important", index: 4)
    model.pendingRetryTarget = (UUID(), .listenAndRepeat, target)
    model.selectedSessionID = UUID()
    #expect(model.pendingRetryTarget == nil)

    model.pendingRetryTarget = (UUID(), .listenAndRepeat, target)
    model.selectedTakeID = UUID()
    #expect(model.pendingRetryTarget == nil)
  }

  @Test("A retry that cannot start does not leave its target pinned")
  func retryThatDoesNotStartClearsTarget() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let target = retargetFixture(word: "important", index: 4)
    model.mimicPhase = .playingReference
    model.startRetryPractice(pinning: (UUID(), .listenAndRepeat, target))
    #expect(model.pendingRetryTarget == nil)

    model.mimicPhase = .ready
    model.isRecording = true
    model.startRetryPractice(pinning: (UUID(), .listenAndRepeat, target))
    #expect(model.pendingRetryTarget == nil)
  }

  @Test("Skip and dismiss survive saves and are forgotten with their take or session")
  func retryCardStateLifetime() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let (url, firstID) = try prepareAudio(model)
    let sessionID = try #require(model.selectedSessionID)
    let secondID = UUID()
    let analysis = try AudioAnalyzer().analyze(url: url)
    model.sessions = [
      CoachingSession(
        id: sessionID, name: "Takes", mode: .general, prompt: "", keepsRecordings: true,
        takes: [
          PracticeSession(id: firstID, audioURL: url, result: analysis),
          PracticeSession(id: secondID, audioURL: url, result: analysis),
        ])
    ]
    model.pendingCaptureIsNewSession = false
    model.selectedTakeID = firstID
    #expect(model.persist(analysisTakeIDs: [firstID, secondID]))
    model.skipRetryCard(for: firstID)
    model.dismissRetryCard(for: firstID)
    model.skipRetryCard(for: secondID)
    model.dismissRetryCard(for: secondID)

    model.deleteTake(sessionID: sessionID, takeID: firstID)
    #expect(model.skippedRetryCardTakeIDs == [secondID])
    #expect(model.dismissedRetryCardTakeIDs == [secondID])

    model.deleteSession(sessionID)
    #expect(model.skippedRetryCardTakeIDs.isEmpty)
    #expect(model.dismissedRetryCardTakeIDs.isEmpty)
  }

  @Test("Re-transcribing a retry take keeps its pinned target")
  func retranscriptionKeepsSavedTarget() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root) { _, _, _ in helloThereOutcome }
    let (url, takeID) = try prepareAudio(model)
    let analysis = try AudioAnalyzer().analyze(url: url)
    let target = retargetFixture(word: "there", index: 1)
    let attempt = PracticeSession(
      id: takeID, audioURL: url, result: analysis,
      transcription: TranscriptionResult(text: "Old", words: []), savedTarget: target)
    let sessionID = try #require(model.selectedSessionID)
    model.sessions = [
      CoachingSession(
        id: sessionID, name: "Retry", mode: .general, prompt: "", keepsRecordings: true,
        takes: [attempt])
    ]
    model.pendingCaptureIsNewSession = false
    model.selectedTakeID = takeID
    #expect(model.persist(analysisTakeIDs: [takeID]))

    await model.retranscribeSelectedTake()?.value

    #expect(model.errorMessage == nil)
    #expect(try model.store.load().first?.latestTake?.savedTarget == target)
  }

  @Test("Re-transcribing the reference drops targets that no longer match its words")
  func referenceRetranscriptionClearsStaleTargets() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root) { _, _, _ in helloThereOutcome }
    let (url, referenceID) = try prepareAudio(model)
    let analysis = try AudioAnalyzer().analyze(url: url)
    let reference = PracticeSession(
      id: referenceID, audioURL: url, result: analysis,
      transcription: TranscriptionResult(text: "Old", words: []))
    let keptID = UUID()
    let droppedID = UUID()
    let missingID = UUID()
    let kept = PracticeSession(
      id: keptID, audioURL: url, result: analysis,
      savedTarget: retargetFixture(word: "THERE", index: 1))
    let dropped = PracticeSession(
      id: droppedID, audioURL: url, result: analysis,
      savedTarget: retargetFixture(word: "there", index: 0))
    let missing = PracticeSession(
      id: missingID, audioURL: url, result: analysis,
      savedTarget: retargetFixture(word: "there", index: 7))
    let sessionID = try #require(model.selectedSessionID)
    model.sessions = [
      CoachingSession(
        id: sessionID, name: "Reference", mode: .mimic, prompt: "", keepsRecordings: true,
        takes: [kept, dropped, missing],
        mimicReference: MimicReference(
          sourceName: "Fixture", take: reference, sourceStart: 0, sourceEnd: 1))
    ]
    model.pendingCaptureIsNewSession = false
    #expect(model.persist(analysisTakeIDs: [referenceID, keptID, droppedID, missingID]))

    await model.retranscribeMimicReference()?.value

    #expect(model.errorMessage == nil)
    let takes = try #require(model.store.load().first?.takes)
    #expect(takes.first { $0.id == keptID }?.savedTarget != nil)
    #expect(takes.first { $0.id == droppedID }?.savedTarget == nil)
    #expect(takes.first { $0.id == missingID }?.savedTarget == nil)
  }

  private func retargetFixture(word: String, index: Int) -> TargetFocus {
    TargetFocus(
      referenceWordIndex: index, word: word, kind: .pitch, gap: 6,
      referenceRange: 0.5...0.9, takeRange: 0.5...0.9)
  }

  @Test(
    "Invalid retries preserve replace-only takes and clear rejected Mimic recovery",
    arguments: [PracticeMode.general, .mimic])
  func existingRecording(mode: PracticeMode) async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let (existingURL, existingTakeID) = try prepareAudio(model)
    model.pendingImportSourceURL = URL(fileURLWithPath: "/tmp/original.wav")
    await model.analyze(url: existingURL, takeID: existingTakeID).value
    let sessionID = try #require(model.selectedSessionID)
    model.sessions[0].keepsRecordings = false
    model.sessions[0].mode = mode
    #expect(model.persist())
    let rejectedID = UUID()
    let rejectedURL = try model.store.recordingURL(sessionID: sessionID, takeID: rejectedID)
    try writeAudio(to: rejectedURL, amplitude: 0)
    if mode == .mimic {
      model.pendingMimicAudio = (rejectedURL, rejectedID)
      model.pendingMimicSessionID = sessionID
    }

    await model.analyze(url: rejectedURL, takeID: rejectedID).value

    #expect(model.sessions[0].takes.map(\.id) == [existingTakeID])
    #expect(try model.store.load()[0].takes.map(\.id) == [existingTakeID])
    #expect(FileManager.default.fileExists(atPath: existingURL.path))
    #expect(!FileManager.default.fileExists(atPath: rejectedURL.path))
    #expect(model.pendingMimicAudio == nil)
    #expect(model.pendingMimicSessionID == nil)
    #expect(model.mimicPhase == .ready)
  }

  @Test(
    "New recording language follows the selected engine",
    arguments: TranscriptionEnginePreference.allCases)
  func speechLanguageRouting(engine: TranscriptionEnginePreference) async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root) { _, requestedEngine, locale in
      #expect(requestedEngine == engine)
      #expect(locale?.identifier == (engine == .system ? "ja_JP" : nil))
      return TranscriptionOutcome(
        result: TranscriptionResult(text: "Recognized speech", words: []), engine: engine)
    }
    model.transcriptionEngine = engine
    model.transcriptionLocaleIdentifier = "ja_JP"
    let (url, takeID) = try prepareAudio(model)

    await model.analyze(url: url, takeID: takeID).value

    #expect(model.sessions.count == 1)
    #expect(
      try model.store.load().first?.transcriptionLocaleIdentifier
        == (engine == .system ? "ja_JP" : nil))
  }

  @Test(
    "Re-transcription preserves audio and acoustics, including on failure",
    arguments: [false, true], [false, true])
  func retranscription(isReference: Bool, shouldFail: Bool) async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root) { _, engine, locale in
      #expect(engine == .parakeet)
      #expect(locale == nil)
      if shouldFail { throw TranscriptionError.noSpeechRecognized }
      return TranscriptionOutcome(
        result: TranscriptionResult(text: "Bonjour", words: [], engine: .parakeet),
        engine: .parakeet)
    }
    let (url, takeID) = try prepareAudio(model)
    let audio = try Data(contentsOf: url)
    let original = PracticeSession(
      id: takeID, audioURL: url, result: try AudioAnalyzer().analyze(url: url),
      transcription: TranscriptionResult(text: "Original", words: []), words: [])
    let sessionID = try #require(model.selectedSessionID)
    model.sessions = [
      CoachingSession(
        id: sessionID, name: "Transcript fixture", mode: isReference ? .mimic : .general,
        prompt: "",
        keepsRecordings: true, takes: isReference ? [] : [original],
        mimicReference: isReference
          ? MimicReference(
            sourceName: "Fixture", take: original, sourceStart: 0, sourceEnd: 1) : nil)
    ]
    model.pendingCaptureIsNewSession = false
    model.selectedTakeID = takeID
    model.transcriptionEngine = .parakeet
    model.transcriptionLocaleIdentifier = "ja_JP"
    #expect(model.persist(analysisTakeIDs: [takeID]))
    if !isReference { _ = model.report }

    let task = try #require(
      isReference
        ? model.retranscribeMimicReference() : model.retranscribeSelectedTake())
    await task.value

    let reloaded = try #require(model.store.load().first)
    let updated = try #require(isReference ? reloaded.mimicReference?.take : reloaded.latestTake)
    #expect(try Data(contentsOf: url) == audio)
    #expect(updated.id == original.id && updated.createdAt == original.createdAt)
    #expect(updated.result == original.result)
    #expect(reloaded.transcriptionLocaleIdentifier == nil)
    #expect(!model.isAnalyzing)
    if shouldFail {
      #expect(updated == original)
      #expect(model.errorMessage != nil)
    } else {
      #expect(updated.transcription?.text == "Bonjour")
      #expect(updated.transcription?.engine == .parakeet)
      #expect(updated.transcription?.localeIdentifier == nil)
      #expect(model.errorMessage == nil)
      #expect(model.reportCache == nil)
    }
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("recording-tests-\(UUID())")
  }

  private func makeModel(
    root: URL,
    transcribe:
      @escaping @Sendable (URL, TranscriptionEnginePreference, Locale?) async throws
      -> TranscriptionOutcome = { _, _, _ in
        TranscriptionOutcome(result: TranscriptionResult(text: "Hello", words: []), engine: .system)
      }
  ) throws -> AppModel {
    let dependencies = AppDependencies(
      recorder: AudioRecorder(), systemAudioCapture: SystemAudioCapture(),
      sessionStore: try SessionStore(rootURL: root),
      sessionChatResponder: LocalSessionChatResponder(),
      transcribe: transcribe)
    return AppModel(loadPersistedData: false, dependencies: dependencies)
  }

  private func prepareAudio(
    _ model: AppModel, amplitude: Float = 0.3, frameCount: AVAudioFrameCount = 16_000
  ) throws -> (URL, UUID) {
    model.prepareStandaloneCapture()
    let sessionID = try #require(model.selectedSessionID)
    let takeID = UUID()
    let url = try model.store.recordingURL(sessionID: sessionID, takeID: takeID)
    try writeAudio(to: url, amplitude: amplitude, frameCount: frameCount)
    model.recordingURL = url
    model.recordingTakeID = takeID
    return (url, takeID)
  }

  private func writeAudio(
    to url: URL, amplitude: Float, frameCount: AVAudioFrameCount = 16_000
  ) throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    guard frameCount > 0 else { return }
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
    buffer.frameLength = frameCount
    let channel = try #require(buffer.floatChannelData?[0])
    for index in 0..<Int(frameCount) {
      channel[index] = amplitude * Float(sin(2 * .pi * 160 * Double(index) / 16_000))
    }
    try file.write(from: buffer)
  }

  private func expectRejected(_ model: AppModel, root: URL, url: URL, title: String) throws {
    #expect(model.sessions.isEmpty)
    #expect(try model.store.load().isEmpty)
    #expect(model.errorTitle == title)
    #expect(model.errorMessage != nil)
    #expect(model.toastMessage == nil)
    #expect(!model.isAnalyzing)
    #expect(model.recordingURL == nil)
    #expect(model.recordingTakeID == nil)
    #expect(!model.pendingCaptureIsNewSession)
    #expect(model.selectedSessionID == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(
      !FileManager.default.fileExists(
        atPath: root.appendingPathComponent("session-library.json").path))
  }
}
