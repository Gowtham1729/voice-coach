import AVFoundation
import Foundation
import Testing
import VoiceCoachCore
import VoiceCoachSession

@testable import VoiceCoachApp

@Suite("Menu bar quick practice", .serialized)
@MainActor
struct QuickPracticeTests {
  @Test("Capture stays in the background; repeated clicks cannot stop it")
  func startsInBackground() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    fixture.model.destination = .library
    let selection = UUID()
    fixture.model.selectedSessionID = selection

    fixture.model.startMenuBarReferenceCapture()
    let url = try #require(fixture.model.mimicReferenceCaptureURL)
    fixture.model.startMenuBarReferenceCapture()
    fixture.model.startHomeRecording()
    fixture.model.requestPermissionAndRecord()
    fixture.model.importClip()

    #expect(fixture.capture.startCount == 1)
    #expect(fixture.capture.stopCount == 0)
    #expect(fixture.model.isCapturingMimicReference)
    #expect(fixture.model.hasMenuBarReference)
    #expect(fixture.model.destination == .library)
    #expect(fixture.model.selectedSessionID == selection)
    #expect(fixture.model.mimicReferenceCaptureURL == url)
    #expect(fixture.model.sessions.isEmpty)
    #expect(!fixture.model.isRequestingPermission)
  }

  @Test(
    "Quick capture does not interrupt existing work",
    arguments: ["recording", "analysis", "permission", "preparing", "count-in", "reference", "draft", "unsaved"])
  func busyWork(state: String) throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    switch state {
    case "recording": fixture.model.isRecording = true
    case "analysis": fixture.model.isAnalyzing = true
    case "permission": fixture.model.isRequestingPermission = true
    case "preparing": fixture.model.mimicIsPreparing = true
    case "count-in": fixture.model.mimicPhase = .countIn(2)
    case "reference": fixture.model.destination = .mimicStart
    case "draft":
      fixture.model.mimicDraft = MimicReferenceDraft(
        id: UUID(), url: fixture.root.appendingPathComponent("draft.wav"),
        sourceName: "Existing", duration: 2, peaks: [], source: .importedAudio)
    case "unsaved":
      let id = UUID()
      fixture.model.selectedSessionID = id
      fixture.model.pendingMimicSessionID = id
      fixture.model.pendingMimicAudio = (fixture.root.appendingPathComponent("take.wav"), UUID())
    default: Issue.record("Unknown fixture state")
    }
    let destination = fixture.model.destination
    fixture.model.startMenuBarReferenceCapture()
    #expect(!fixture.model.canStartQuickPractice)
    #expect(!fixture.model.hasMenuBarReference)
    #expect(fixture.capture.startCount == 0)
    #expect(fixture.model.destination == destination)
  }

  @Test("Stop opens the normal reference draft and saves through the existing practice flow")
  func reviewAndSave() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    fixture.model.startMenuBarReferenceCapture()
    let url = try #require(fixture.model.mimicReferenceCaptureURL)
    fixture.model.mimicReferenceCaptureElapsed = 2

    fixture.model.reviewMenuBarReference()
    #expect(!fixture.model.isCapturingMimicReference)
    #expect(fixture.model.destination == .mimicStart)
    #expect(fixture.capture.stopCount == 1)
    try await waitUntil { !fixture.model.mimicIsPreparing }
    let draft = try #require(fixture.model.mimicDraft)
    #expect(draft.url == url && draft.source == .systemAudio)
    #expect(fixture.model.sessions.isEmpty)
    fixture.model.createMimicSession(name: "Quick practice fixture", start: 0, end: 1)
    try await waitUntil { !fixture.model.mimicIsPreparing }

    let saved = try #require(fixture.model.sessions.first)
    #expect(saved.mimicReference?.take.takeSource == .systemAudio)
    #expect(fixture.model.destination == .practice(saved.id))
    #expect(!fixture.model.hasMenuBarReference)
    #expect(try fixture.model.store.load().first?.id == saved.id)
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test("Automatic stop leaves a reviewable clip without bringing up a sheet")
  func backgroundFinish() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    fixture.model.destination = .library
    fixture.model.startMenuBarReferenceCapture()
    fixture.model.mimicReferenceCaptureElapsed = 90
    // The timer and interruption callback both use this shared finish path.
    fixture.model.finishMimicReferenceCapture()
    try await waitUntil { !fixture.model.mimicIsPreparing }
    #expect(fixture.model.destination == .library)
    #expect(fixture.model.hasMenuBarReference)
    #expect(fixture.model.mimicDraft != nil)
    #expect(!fixture.model.canStartQuickPractice)
    fixture.model.reviewMenuBarReference()
    #expect(fixture.model.destination == .mimicStart)
  }

  @Test("Reference actions preserve a background capture", arguments: [false, true])
  func referenceActionsPreserveCapture(afterStop: Bool) async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    fixture.model.startMenuBarReferenceCapture()
    let url = try #require(fixture.model.mimicReferenceCaptureURL)
    let take = PracticeSession(
      audioURL: url, result: try AudioAnalyzer().analyze(url: url))
    let session = CoachingSession(
      name: "Existing recording", mode: .general, prompt: "", keepsRecordings: true, takes: [take])
    fixture.model.sessions = [session]
    fixture.model.selectedSessionID = session.id
    fixture.model.selectedTakeID = take.id
    fixture.model.destination = .take(session.id, take.id)
    if afterStop {
      fixture.model.mimicReferenceCaptureElapsed = 2
      fixture.model.finishMimicReferenceCapture()
      try await waitUntil { !fixture.model.mimicIsPreparing }
    }
    let destination = fixture.model.destination
    let preparationID = fixture.model.mimicPreparationID
    fixture.model.startMimic()
    fixture.model.useCurrentRecordingAsMimicReference()
    fixture.model.chooseMimicReference()
    #expect(fixture.model.hasMenuBarReference)
    #expect(fixture.model.isCapturingMimicReference == !afterStop)
    #expect(fixture.model.mimicPreparationID == preparationID)
    #expect(fixture.model.destination == destination)
    #expect(FileManager.default.fileExists(atPath: url.path))
  }

  @Test("Quit protection includes in-app drafts, count-in, and unsaved takes")
  func unsavedAudioProtection() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    #expect(!fixture.model.hasUnsavedAudio)
    fixture.model.mimicDraft = MimicReferenceDraft(
      id: UUID(), url: fixture.root.appendingPathComponent("draft.wav"),
      sourceName: "Imported clip", duration: 2, peaks: [], source: .importedAudio)
    #expect(fixture.model.hasUnsavedAudio)
    fixture.model.mimicDraft = nil
    fixture.model.mimicPhase = .countIn(2)
    #expect(fixture.model.hasUnsavedAudio)
    fixture.model.mimicPhase = .ready
    fixture.model.pendingMimicAudio = (fixture.root.appendingPathComponent("take.wav"), UUID())
    #expect(fixture.model.hasUnsavedAudio)
    fixture.model.pendingMimicAudio = nil
    #expect(!fixture.model.hasUnsavedAudio)
  }

  @Test("Delayed capture startup blocks conflicts and cleans up after cancellation", arguments: ["granted", "denied", "cancelled"])
  func delayedStartup(outcome: String) throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    fixture.capture.delaysStart = true
    fixture.model.destination = .library
    fixture.model.startMenuBarReferenceCapture()
    let url = try #require(fixture.model.mimicReferenceCaptureURL)
    #expect(fixture.model.isRequestingPermission)
    #expect(fixture.model.hasMenuBarReference)
    #expect(!fixture.model.isCapturingMimicReference)
    #expect(fixture.model.mimicReferenceCaptureTimer == nil)
    fixture.model.reviewMenuBarReference()
    fixture.model.startMenuBarReferenceCapture()
    fixture.model.startHomeRecording()
    fixture.model.chooseMimicReference()
    #expect(fixture.capture.requestCount == 1)
    #expect(fixture.model.destination == .library)
    if outcome == "cancelled" {
      fixture.model.discardMenuBarReference()
      #expect(!fixture.model.hasMenuBarReference)
      #expect(!fixture.model.canStartQuickPractice)
    }
    fixture.capture.shouldFail = outcome == "denied"
    fixture.capture.completeStart()
    #expect(!fixture.model.isRequestingPermission)
    if outcome == "granted" {
      #expect(fixture.model.isCapturingMimicReference)
      #expect(fixture.model.hasMenuBarReference)
      #expect(fixture.model.mimicReferenceCaptureTimer != nil)
      fixture.model.discardMenuBarReference()
    } else {
      #expect(!fixture.model.isCapturingMimicReference)
      #expect(!fixture.model.hasMenuBarReference)
      #expect(fixture.model.mimicReferenceCaptureTimer == nil)
      #expect(!FileManager.default.fileExists(atPath: url.path))
      #expect(fixture.model.canStartQuickPractice)
      #expect((fixture.model.errorMessage != nil) == (outcome == "denied"))
    }
    #expect(fixture.model.sessions.isEmpty)
  }

  @Test("Discard removes staged audio and invalidates pending preparation", arguments: [false, true])
  func discard(afterStop: Bool) async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    fixture.model.startMenuBarReferenceCapture()
    let url = try #require(fixture.model.mimicReferenceCaptureURL)
    if afterStop {
      fixture.model.mimicReferenceCaptureElapsed = 2
      fixture.model.finishMimicReferenceCapture()
      try await waitUntil { !fixture.model.mimicIsPreparing }
    }
    fixture.model.discardMenuBarReference()
    #expect(!fixture.model.isCapturingMimicReference)
    #expect(!fixture.model.hasMenuBarReference)
    #expect(fixture.model.mimicDraft == nil)
    #expect(fixture.model.mimicPreparationID == nil)
    #expect(fixture.model.mimicReferenceCaptureTimer == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(fixture.model.canStartQuickPractice)
    #expect(fixture.model.sessions.isEmpty)
  }

  @Test("Silent, short, and failed captures reset quick practice", arguments: ["silent", "short", "failed"])
  func rejectedCapture(kind: String) throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    fixture.capture.heardAudio = kind != "silent"
    fixture.capture.shouldFail = kind == "failed"
    fixture.model.startMenuBarReferenceCapture()
    let url = fixture.capture.lastURL
    if kind != "failed" {
      fixture.model.mimicReferenceCaptureElapsed = kind == "short" ? 0.1 : 2
      fixture.model.reviewMenuBarReference()
    }
    #expect(!fixture.model.hasMenuBarReference)
    #expect(!fixture.model.isCapturingMimicReference)
    #expect(fixture.model.errorTitle == "Capture failed")
    #expect(fixture.model.errorMessage != nil)
    #expect(fixture.model.destination == .home)
    #expect(fixture.model.sessions.isEmpty)
    #expect(fixture.model.canStartQuickPractice)
    if let url { #expect(!FileManager.default.fileExists(atPath: url.path)) }
  }

  private func waitUntil(_ condition: () -> Bool) async throws {
    // Other app suites also analyze audio on this runner. Allow their main-actor
    // work to finish rather than treating scheduling delay as a capture failure.
    let deadline = ContinuousClock.now + .seconds(30)
    while !condition() {
      guard ContinuousClock.now < deadline else { throw TestTimeout.expired }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

private enum TestTimeout: Error { case expired }

@MainActor
private struct Fixture {
  let root: URL
  let capture: TestSystemAudioCapture
  let model: AppModel

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("quick-practice-tests-\(UUID())")
    capture = TestSystemAudioCapture()
    model = AppModel(
      loadPersistedData: false,
      dependencies: AppDependencies(
        recorder: AudioRecorder(), systemAudioCapture: capture,
        sessionStore: try SessionStore(rootURL: root), sessionChatResponder: LocalSessionChatResponder(),
        transcribe: { _, _, _ in
          TranscriptionOutcome(result: TranscriptionResult(text: "Hello", words: []), engine: .system)
        }))
  }

  func cleanUp() {
    model.cancelMimicPreparation()
    model.transcriptionSetupTask?.cancel()
    model.systemTranscriptionStatusTask?.cancel()
    try? FileManager.default.removeItem(at: root)
  }
}

private final class TestSystemAudioCapture: SystemAudioCapturing {
  var onCaptureInterrupted: (() -> Void)?
  var heardAudio = true
  var shouldFail = false
  var startCount = 0
  var stopCount = 0
  var lastURL: URL?
  var delaysStart = false
  var requestCount = 0
  private var pendingStart: (@MainActor () -> Void)?

  @MainActor
  func requestStart(url: URL, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
    requestCount += 1
    if delaysStart {
      pendingStart = { completion(Result { try self.start(url: url) }) }
    } else {
      completion(Result { try start(url: url) })
    }
  }

  @MainActor
  func completeStart() {
    let pending = pendingStart
    pendingStart = nil
    pending?()
  }

  func peakLevel() -> Float { -20 }
  func stop() { stopCount += 1 }

  private func start(url: URL) throws {
    startCount += 1
    lastURL = url
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000))
    buffer.frameLength = 96_000
    let channel = try #require(buffer.floatChannelData?[0])
    for index in 0..<96_000 {
      channel[index] = 0.3 * Float(sin(2 * .pi * 160 * Double(index) / 48_000))
    }
    try file.write(from: buffer)
    if shouldFail { throw SystemAudioCaptureError.setupFailed }
  }
}
