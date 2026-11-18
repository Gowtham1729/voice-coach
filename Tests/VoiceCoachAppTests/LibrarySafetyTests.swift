import AVFoundation
import Foundation
import Testing
import VoiceCoachCore
import VoiceCoachSession

@testable import VoiceCoachApp

@MainActor
private final class StubRecorder: AudioRecording {
  var onPlaybackFinished: (() -> Void)?
  var onRecordingInterrupted: (() -> Void)?
  var currentTime: TimeInterval = 0
  var playbackVolume: Float = 1
  var startError: Error?
  var playedVolumes: [Float] = []

  func start(url: URL) throws { if let startError { throw startError } }
  func stop() {}
  func peakLevel() -> Float { -80 }
  func play(url: URL, from time: TimeInterval) throws { playedVolumes.append(playbackVolume) }
  func pausePlayback() {}
  func stopPlayback() {}
  func seek(to time: TimeInterval) {}
}

private actor Gate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func open() {
    isOpen = true
    for waiter in waiters { waiter.resume() }
    waiters = []
  }
}

@Suite("Library safety")
@MainActor
struct LibrarySafetyTests {
  @Test("A library that failed to load is never overwritten")
  func unreadableLibraryIsNotOverwritten() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let libraryURL = root.appendingPathComponent("session-library.json")
    let garbage = Data("{ not a library".utf8)
    try garbage.write(to: libraryURL)
    let model = try makeModel(root: root, loadPersistedData: true)
    #expect(model.libraryLoadFailed)
    model.clearError()

    model.startHomeRecording()
    #expect(model.errorTitle == "Practices couldn’t be loaded")
    #expect(model.errorMessage?.hasPrefix("Nothing was saved") == true)
    #expect(!model.isRecording)
    #expect(model.selectedSessionID == nil)

    model.sessions = [
      CoachingSession(name: "New", mode: .general, prompt: "", keepsRecordings: true)
    ]
    #expect(!model.persist())
    #expect(try Data(contentsOf: libraryURL) == garbage)
  }

  @Test("Unreadable takes are reported once and kept when the library is saved")
  func skippedTakesToast() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let sessionID = UUID()
    let (url, takeID) = try writeTake(store: store, sessionID: sessionID)
    let session = CoachingSession(
      id: sessionID, name: "Kept", mode: .general, prompt: "", keepsRecordings: true,
      takes: [PracticeSession(id: takeID, audioURL: url, result: try AudioAnalyzer().analyze(url: url))])
    try store.save([session])
    try FileManager.default.removeItem(at: store.analysisURL(sessionID: sessionID, takeID: takeID))

    let model = try makeModel(root: root, loadPersistedData: true)

    #expect(!model.libraryLoadFailed)
    #expect(model.toastMessage == "Some recordings couldn’t be read and were left on disk.")
    #expect(model.sessions.isEmpty)
    #expect(try String(contentsOf: root.appendingPathComponent("session-library.json"), encoding: .utf8).contains(takeID.uuidString))
  }

  @Test("Finishing an analysis lands in the session it started in")
  func analysisKeepsItsSession() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    let model = try makeModel(root: root) { _, _, _ in
      await gate.wait()
      return TranscriptionOutcome(
        result: TranscriptionResult(text: "Hello", words: []), engine: .system)
    }
    let sessionA = UUID()
    let sessionB = UUID()
    model.sessions = [
      CoachingSession(
        id: sessionA, name: "A", mode: .general, prompt: "", keepsRecordings: true),
      CoachingSession(
        id: sessionB, name: "B", mode: .general, prompt: "", keepsRecordings: true),
    ]
    model.selectedSessionID = sessionA
    let takeID = UUID()
    let url = try model.store.recordingURL(sessionID: sessionA, takeID: takeID)
    try writeAudio(to: url)

    let task = model.analyze(url: url, takeID: takeID)
    model.selectedSessionID = sessionB
    await gate.open()
    await task.value

    #expect(model.sessions.first { $0.id == sessionA }?.takes.map(\.id) == [takeID])
    #expect(model.sessions.first { $0.id == sessionB }?.takes.isEmpty == true)
    #expect(model.destination == .take(sessionA, takeID))
  }

  @Test("Opening another recording is refused while a take is being analysed")
  func navigationRefusedWhileAnalyzing() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let (first, second) = (try plainSession(model), try plainSession(model))
    model.sessions = [first, second]
    model.selectedSessionID = first.id
    model.isAnalyzing = true

    #expect(!model.canNavigate)
    model.openTake(sessionID: second.id)
    model.resumeSession(second.id)

    #expect(model.selectedSessionID == first.id)
    #expect(model.destination == .home)
  }

  @Test("Deleting a take from the Library leaves the selection alone")
  func deleteTakeKeepsSelection() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let (first, second) = (try plainSession(model), try plainSession(model))
    model.sessions = [first, second]
    #expect(model.persist(analysisTakeIDs: Set((first.takes + second.takes).map(\.id))))
    model.selectedSessionID = first.id

    model.deleteTake(sessionID: second.id, takeID: second.takes[0].id)

    #expect(model.selectedSessionID == first.id)
    #expect(model.sessions.map(\.id) == [first.id])
  }

  @Test("Deleting the last take of a recording removes its session and folder")
  func deleteLastTakeRemovesSession() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let session = try plainSession(model)
    model.sessions = [session]
    #expect(model.persist(analysisTakeIDs: Set(session.takes.map(\.id))))
    let folder = try model.store.takeDirectory(sessionID: session.id)

    model.deleteTake(sessionID: session.id, takeID: session.takes[0].id)

    #expect(model.sessions.isEmpty)
    #expect(try model.store.load().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
  }

  @Test("Delete and archive are refused while recording")
  func mutationsRefusedWhileRecording() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let session = try plainSession(model)
    model.sessions = [session]
    model.isRecording = true

    model.deleteTake(sessionID: session.id, takeID: session.takes[0].id)
    model.deleteSession(session.id)

    #expect(model.sessions.count == 1 && model.sessions[0].takes.count == 1)
  }

  @Test("A failed save rolls back archiving without announcing it")
  func archiveRollsBack() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    let mimic = CoachingSession(
      name: "Ref", mode: .mimic, prompt: "", keepsRecordings: true)
    model.sessions = [mimic]
    try breakLibraryFile(root)

    model.archiveMimic(mimic.id)

    #expect(model.sessions.first?.archived == false)
    #expect(model.toastMessage != "Practice archived")
    #expect(model.errorTitle == "Save failed")
  }

  @Test("A second stop does nothing")
  func stopRecordingIsIdempotent() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    model.stopRecording()
    #expect(model.errorMessage == nil)
    #expect(!model.isAnalyzing)
  }

  @Test("Captures under the gate are rejected with accurate copy")
  func shortRecording() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    model.prepareStandaloneCapture()
    model.isRecording = true
    model.elapsed = AppModel.minimumCaptureDuration - 0.1

    model.stopRecording()

    #expect(model.errorTitle == "Recording too short")
    #expect(model.errorMessage == "Record a little longer and try again.")
    #expect(model.selectedSessionID == nil)
  }

  @Test("An analyzer failure leaves no audio and no pending folder")
  func analyzerFailureCleansUp() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try makeModel(root: root)
    model.prepareStandaloneCapture()
    let sessionID = try #require(model.selectedSessionID)
    let takeID = UUID()
    let url = try model.store.recordingURL(sessionID: sessionID, takeID: takeID)
    try Data("this is not audio".utf8).write(to: url)

    await model.analyze(url: url, takeID: takeID).value

    #expect(model.errorTitle == "Analysis failed")
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    #expect(model.sessions.isEmpty)
    #expect(model.selectedSessionID == nil)
    #expect(!model.pendingCaptureIsNewSession)
  }

  @Test("A recorder that cannot start leaves no pending folder")
  func recorderStartFailureCleansUp() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = StubRecorder()
    recorder.startError = RecorderError.microphoneDenied
    let model = try makeModel(root: root, recorder: recorder)
    model.prepareStandaloneCapture()
    let sessionID = try #require(model.selectedSessionID)
    let folder = root.appendingPathComponent("Sessions/\(sessionID.uuidString)")
    #expect(FileManager.default.fileExists(atPath: folder.path))

    model.beginRecording()

    #expect(!model.isRecording)
    #expect(model.selectedSessionID == nil)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
  }

  @Test("Take playback resets the volume a reference clip lowered")
  func takePlaybackVolume() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = StubRecorder()
    let model = try makeModel(root: root, recorder: recorder)
    let session = try plainSession(model)
    model.sessions = [session]
    model.selectedSessionID = session.id
    recorder.playbackVolume = 0.2

    model.playCurrent()

    #expect(recorder.playedVolumes == [1])
  }

  // MARK: - Helpers

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("library-safety-\(UUID())")
  }

  private func makeModel(
    root: URL,
    loadPersistedData: Bool = false,
    recorder: (any AudioRecording)? = nil,
    transcribe:
      @escaping @Sendable (URL, TranscriptionEnginePreference, Locale?) async throws
      -> TranscriptionOutcome = { _, _, _ in
        TranscriptionOutcome(result: TranscriptionResult(text: "Hello", words: []), engine: .system)
      }
  ) throws -> AppModel {
    let dependencies = AppDependencies(
      recorder: recorder ?? AudioRecorder(), systemAudioCapture: SystemAudioCapture(),
      sessionStore: try SessionStore(rootURL: root),
      sessionChatResponder: LocalSessionChatResponder(),
      transcribe: transcribe)
    return AppModel(loadPersistedData: loadPersistedData, dependencies: dependencies)
  }

  /// A plain recording with real audio on disk.
  private func plainSession(_ model: AppModel) throws -> CoachingSession {
    let sessionID = UUID()
    let (url, takeID) = try writeTake(store: model.store, sessionID: sessionID)
    return CoachingSession(
      id: sessionID, name: "Recording", mode: .general, prompt: "", keepsRecordings: true,
      takes: [
        PracticeSession(id: takeID, audioURL: url, result: try AudioAnalyzer().analyze(url: url))
      ])
  }

  private func writeTake(store: any SessionStoring, sessionID: UUID) throws -> (URL, UUID) {
    let takeID = UUID()
    let url = try store.recordingURL(sessionID: sessionID, takeID: takeID)
    try writeAudio(to: url)
    return (url, takeID)
  }

  private func writeAudio(to url: URL) throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
    buffer.frameLength = 16_000
    let channel = try #require(buffer.floatChannelData?[0])
    for index in 0..<16_000 {
      channel[index] = 0.3 * Float(sin(2 * .pi * 160 * Double(index) / 16_000))
    }
    try file.write(from: buffer)
  }

  /// Makes every index write fail by putting a non-empty directory where the file goes.
  private func breakLibraryFile(_ root: URL) throws {
    let libraryURL = root.appendingPathComponent("session-library.json")
    try? FileManager.default.removeItem(at: libraryURL)
    try FileManager.default.createDirectory(
      at: libraryURL.appendingPathComponent("blocker"), withIntermediateDirectories: true)
  }
}
