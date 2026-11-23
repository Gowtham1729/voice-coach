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
    let fixture = try QuickPracticeFixture()
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
    let fixture = try QuickPracticeFixture()
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
    let fixture = try QuickPracticeFixture()
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
    let creation = try #require(
      fixture.model.createPracticeSessions(
        draftID: draft.id,
        selections: [PracticeClipSelection(phraseID: nil, start: 0, end: 1)]))
    await creation.value

    let saved = try #require(fixture.model.sessions.first)
    #expect(saved.mimicReference?.take.takeSource == .systemAudio)
    #expect(fixture.model.destination == .practice(saved.id))
    #expect(!fixture.model.hasMenuBarReference)
    #expect(try fixture.model.store.load().first?.id == saved.id)
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test("Automatic stop leaves a reviewable clip without bringing up a sheet")
  func backgroundFinish() async throws {
    let fixture = try QuickPracticeFixture()
    defer { fixture.cleanUp() }
    fixture.model.destination = .library
    fixture.model.startMenuBarReferenceCapture()
    fixture.model.mimicReferenceCaptureStartedAt = Date().addingTimeInterval(-91)
    // The same tick the capture timer runs every 50 ms.
    fixture.model.tickMimicReferenceCapture()
    #expect(!fixture.model.isCapturingMimicReference)
    #expect(fixture.capture.stopCount == 1)
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
    let fixture = try QuickPracticeFixture()
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

  @Test("Quit protection covers real audio, not playback or count-in")
  func unsavedAudioProtection() throws {
    let fixture = try QuickPracticeFixture()
    defer { fixture.cleanUp() }
    #expect(!fixture.model.hasUnsavedAudio)
    fixture.model.mimicDraft = MimicReferenceDraft(
      id: UUID(), url: fixture.root.appendingPathComponent("draft.wav"),
      sourceName: "Imported clip", duration: 2, peaks: [], source: .importedAudio)
    #expect(fixture.model.hasUnsavedAudio)
    fixture.model.mimicDraft = nil
    // Playback and count-in hold no audio to lose.
    fixture.model.mimicPhase = .countIn(2)
    #expect(!fixture.model.hasUnsavedAudio)
    fixture.model.mimicPhase = .playingReference
    #expect(!fixture.model.hasUnsavedAudio)
    fixture.model.mimicPhase = .ready
    fixture.model.isRecording = true
    #expect(fixture.model.hasUnsavedAudio)
    fixture.model.isRecording = false
    fixture.model.pendingMimicAudio = (fixture.root.appendingPathComponent("take.wav"), UUID())
    #expect(fixture.model.hasUnsavedAudio)
    fixture.model.pendingMimicAudio = nil
    #expect(!fixture.model.hasUnsavedAudio)
  }

  @Test("Delayed capture startup blocks conflicts and cleans up after cancellation", arguments: ["granted", "denied", "cancelled"])
  func delayedStartup(outcome: String) throws {
    let fixture = try QuickPracticeFixture()
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
      #expect(!fixture.model.isRequestingPermission)
      #expect(fixture.model.canStartQuickPractice)
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
    let fixture = try QuickPracticeFixture()
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
    let fixture = try QuickPracticeFixture()
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


  @Test("Cancelling during the permission dialog returns to idle and the late start tears down")
  func cancelDuringPermission() throws {
    let fixture = try QuickPracticeFixture()
    defer { fixture.cleanUp() }
    fixture.capture.delaysStart = true
    fixture.model.startMenuBarReferenceCapture()
    let url = try #require(fixture.model.mimicReferenceCaptureURL)
    #expect(fixture.model.isRequestingPermission)

    fixture.model.discardMenuBarReference()
    #expect(!fixture.model.isRequestingPermission)
    #expect(!fixture.model.hasMenuBarReference)
    #expect(fixture.model.canStartQuickPractice)

    fixture.capture.completeStart()
    #expect(fixture.capture.stopCount == 1)
    #expect(!fixture.model.isCapturingMimicReference)
    #expect(fixture.model.mimicReferenceCaptureTimer == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(fixture.model.canStartQuickPractice)
  }

  @Test("A stale permission completion cannot disturb a newer capture")
  func staleCompletionIgnored() throws {
    let fixture = try QuickPracticeFixture()
    defer { fixture.cleanUp() }
    fixture.capture.delaysStart = true
    fixture.model.startMenuBarReferenceCapture()
    fixture.model.discardMenuBarReference()
    fixture.model.startMenuBarReferenceCapture()
    let newURL = try #require(fixture.model.mimicReferenceCaptureURL)
    let newID = fixture.model.mimicPreparationID
    #expect(fixture.model.isRequestingPermission)

    fixture.capture.completeStart(at: 0)
    #expect(fixture.model.isRequestingPermission)
    #expect(!fixture.model.isCapturingMimicReference)
    #expect(fixture.model.mimicPreparationID == newID)
    #expect(fixture.model.mimicReferenceCaptureURL == newURL)
    #expect(fixture.capture.stopCount == 0)

    fixture.capture.completeStart(at: 1)
    #expect(fixture.model.isCapturingMimicReference)
    #expect(!fixture.model.isRequestingPermission)
    fixture.model.discardMenuBarReference()
  }

  @Test("Capture errors keep their specific message and can be dismissed")
  func captureErrorFlag() throws {
    let fixture = try QuickPracticeFixture()
    defer { fixture.cleanUp() }
    fixture.capture.shouldFail = true
    fixture.model.startMenuBarReferenceCapture()
    #expect(fixture.model.errorIsFromCapture)
    #expect(fixture.model.errorMessage == SystemAudioCaptureError.setupFailed.errorDescription)
    fixture.model.clearError()
    #expect(!fixture.model.errorIsFromCapture)
    fixture.model.presentError(title: "Save failed", message: "Unrelated")
    #expect(!fixture.model.errorIsFromCapture)
  }

  @Test("Quit cleanup never needs a prompt for a permission wait and removes staged audio")
  func quitCleanup() throws {
    let fixture = try QuickPracticeFixture()
    defer { fixture.cleanUp() }
    fixture.capture.delaysStart = true
    fixture.model.startMenuBarReferenceCapture()
    let url = try #require(fixture.model.mimicReferenceCaptureURL)
    #expect(fixture.model.isRequestingPermission)
    #expect(!fixture.model.hasUnsavedAudio && !fixture.model.isPreparingAudio)
    fixture.model.discardInFlightWorkForQuit()
    #expect(!fixture.model.isRequestingPermission)
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test("A late sheet disappearance keeps a menu bar clip but cancels sheet work")
  func sheetDisappearance() async throws {
    let fixture = try QuickPracticeFixture()
    defer { fixture.cleanUp() }
    fixture.model.destination = .library
    fixture.model.startMenuBarReferenceCapture()
    fixture.model.mimicSheetDidDisappear()
    #expect(fixture.model.isCapturingMimicReference && fixture.model.hasMenuBarReference)
    fixture.model.mimicReferenceCaptureElapsed = 2
    fixture.model.finishMimicReferenceCapture()
    try await waitUntil { !fixture.model.mimicIsPreparing }
    fixture.model.mimicSheetDidDisappear()
    #expect(fixture.model.hasMenuBarReference && fixture.model.mimicDraft != nil)
    #expect(fixture.model.hasMenuBarClipAwaitingReview)
    // A sheet-owned reference is cancelled.
    fixture.model.discardMenuBarReference()
    let url = fixture.root.appendingPathComponent("sheet.wav")
    try Data([0]).write(to: url)
    fixture.model.mimicDraft = MimicReferenceDraft(
      id: UUID(), url: url, sourceName: "Imported", duration: 2, peaks: [], source: .importedAudio)
    fixture.model.mimicSheetDidDisappear()
    #expect(fixture.model.mimicDraft == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test("Stopping review stops playback first")
  func reviewStopsPlayback() async throws {
    let fixture = try QuickPracticeFixture()
    defer { fixture.cleanUp() }
    fixture.model.startMenuBarReferenceCapture()
    fixture.model.isPlaying = true
    fixture.model.mimicReferenceCaptureElapsed = 2
    fixture.model.reviewMenuBarReference()
    #expect(!fixture.model.isPlaying)
    try await waitUntil { !fixture.model.mimicIsPreparing }
  }

  @Test("Phrase search and batch creation block quick practice", arguments: ["finding", "creating"])
  func newBusyStates(state: String) throws {
    let fixture = try QuickPracticeFixture()
    defer { fixture.cleanUp() }
    if state == "finding" {
      fixture.model.mimicIsFindingPhrases = true
    } else {
      fixture.model.practiceClipCreationProgress = (0, 2)
    }
    #expect(!fixture.model.canStartQuickPractice)
    fixture.model.startMenuBarReferenceCapture()
    #expect(fixture.capture.requestCount == 0)
  }

  @Test("A too-short menu bar clip resets every flag")
  func tooShortClip() async throws {
    let fixture = try QuickPracticeFixture()
    defer { fixture.cleanUp() }
    fixture.capture.sampleCount = 24_000
    fixture.model.startMenuBarReferenceCapture()
    fixture.model.mimicReferenceCaptureElapsed = 2
    fixture.model.reviewMenuBarReference()
    try await waitUntil { !fixture.model.mimicIsPreparing }
    #expect(!fixture.model.hasMenuBarReference && fixture.model.mimicDraft == nil)
    #expect(!fixture.model.mimicIsFindingPhrases && !fixture.model.isRequestingPermission)
    #expect(fixture.model.errorTitle == "Clip too short" && fixture.model.errorIsFromCapture)
    #expect(fixture.model.destination == .mimicStart)  // the sheet stays open on the picker with the error
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
struct QuickPracticeFixture {
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

final class TestSystemAudioCapture: SystemAudioCapturing {
  var onCaptureInterrupted: (() -> Void)?
  var heardAudio = true
  var shouldFail = false
  var startCount = 0
  var stopCount = 0
  var lastURL: URL?
  var delaysStart = false
  var requestCount = 0
  var sampleCount = 96_000
  private var pendingStarts: [@MainActor () -> Void] = []

  @MainActor
  func requestStart(url: URL, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
    requestCount += 1
    if delaysStart {
      pendingStarts.append { completion(Result { try self.start(url: url) }) }
    } else {
      completion(Result { try start(url: url) })
    }
  }

  @MainActor
  func completeStart(at index: Int = 0) {
    guard pendingStarts.indices.contains(index) else { return }
    pendingStarts[index]()
  }

  func peakLevel() -> Float { -20 }
  func stop() { stopCount += 1 }

  private func start(url: URL) throws {
    startCount += 1
    lastURL = url
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)))
    buffer.frameLength = AVAudioFrameCount(sampleCount)
    let channel = try #require(buffer.floatChannelData?[0])
    for index in 0..<sampleCount {
      channel[index] = 0.3 * Float(sin(2 * .pi * 160 * Double(index) / 48_000))
    }
    try file.write(from: buffer)
    if shouldFail { throw SystemAudioCaptureError.setupFailed }
  }
}
