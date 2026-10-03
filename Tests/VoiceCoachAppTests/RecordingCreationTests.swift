import AVFoundation
import Foundation
import Testing
import VoiceCoachCore
import VoiceCoachSession
@testable import VoiceCoachApp

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

  @Test("Silent capture and imports do not create library entries",
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
    let model = try makeModel(root: root) { _, _ in
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
    let model = try makeModel(root: root) { _, _ in throw TranscriptionError.noSpeechRecognized }
    let (url, takeID) = try prepareAudio(model)

    await model.analyze(url: url, takeID: takeID).value

    try expectRejected(model, root: root, url: url, title: "No Speech Recognized")
  }

  @Test("Technical transcription failures preserve playable audio",
    arguments: [TranscriptionError.runtimeUnavailable, .invalidOutput, .recognitionFailed("failed")])
  func transcriptionFailure(error: TranscriptionError) async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root) { _, _ in throw error }
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

  @Test("Invalid retries preserve replace-only takes and clear rejected Mimic recovery",
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

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("recording-tests-\(UUID())")
  }

  private func makeModel(
    root: URL,
    transcribe: @escaping @Sendable (URL, TranscriptionEnginePreference) async throws
      -> TranscriptionOutcome = { _, _ in
        TranscriptionOutcome(result: TranscriptionResult(text: "Hello", words: []), engine: .system)
      }
  ) throws -> AppModel {
    let dependencies = AppDependencies(
      recorder: AudioRecorder(), systemAudioCapture: SystemAudioCapture(),
      sessionStore: try SessionStore(rootURL: root), transcribe: transcribe)
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
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("session-library.json").path))
  }
}
