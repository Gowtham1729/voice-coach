import Foundation
import Testing
import VoiceCoachCore
import VoiceCoachSession

@testable import VoiceCoachApp

private actor FakeSoundComparison: SoundComparing {
  var referenceCalls = 0
  var compareCalls = 0
  let fails: Bool
  let unreadableTake: Bool
  var lastTakeWords: [SoundWord?] = []

  init(fails: Bool = false, unreadableTake: Bool = false) {
    self.fails = fails
    self.unreadableTake = unreadableTake
  }

  func installedEngines() -> [SoundEngineInstall] {
    [SoundEngineInstall(id: "lite", sizeBytes: 1, isCurrent: true)]
  }

  func analyzeReference(engineID: String, audioURL: URL, words: [SoundWord]) throws
    -> ReferenceAnalysis
  {
    referenceCalls += 1
    if fails { throw SoundComparisonError.engineNotInstalled(engineID) }
    return ReferenceAnalysis(
      engineID: engineID, engineVersion: SoundComparisonConfiguration.engineVersion, words: words,
      models: [])
  }

  func compare(
    engineID: String, reference: ReferenceAnalysis, takeAudioURL: URL, takeWords: [SoundWord?]
  ) throws -> SoundComparisonResult {
    compareCalls += 1
    lastTakeWords = takeWords
    if unreadableTake { throw SoundComparisonError.unreadableAudio }
    return SoundComparisonResult(
      engineID: engineID, engineVersion: reference.engineVersion, words: [], phones: [])
  }

  func deleteEngine(_ engineID: String) {}
}

@Suite("Sound comparison flow")
@MainActor
struct SoundComparisonFlowTests {
  @Test("The Reference is analysed once per engine and reused for every take")
  func referenceAnalysedOnce() async throws {
    let service = FakeSoundComparison()
    let (model, root, session) = try await makeModel(service)
    defer { try? FileManager.default.removeItem(at: root) }

    for take in session.takes {
      model.selectTake(take.id)
      await model.compareSoundsIfNeeded()?.value
    }

    #expect(await service.referenceCalls == 1)
    #expect(await service.compareCalls == 2)
    #expect(await service.lastTakeWords.map { $0?.text } == ["clear", "steady", "voice"])
    let loaded = try #require(try model.store.load().first)
    #expect(loaded.takes.allSatisfy { $0.sounds?.comparisons["lite"] != nil })
    #expect(loaded.mimicReference?.take.sounds?.referenceAnalyses["lite"] != nil)
  }

  @Test("An engine failure never removes or blocks the take")
  func failureKeepsTake() async throws {
    let (model, root, session) = try await makeModel(FakeSoundComparison(fails: true))
    defer { try? FileManager.default.removeItem(at: root) }
    let take = session.takes[0]
    model.selectTake(take.id)

    await model.compareSoundsIfNeeded()?.value

    #expect(model.soundComparisonStatus(sessionID: session.id, takeID: take.id) == .failed)
    #expect(try model.store.load().first?.takes.map(\.id) == session.takes.map(\.id))
    #expect(model.errorMessage == nil)
  }

  @Test("A missing or unreadable audio file shows why, not a retry")
  func missingAudioIsNotComparable() async throws {
    let service = FakeSoundComparison(unreadableTake: true)
    let (model, root, session) = try await makeModel(service)
    defer { try? FileManager.default.removeItem(at: root) }
    let take = session.takes[0]
    model.selectTake(take.id)

    await model.compareSoundsIfNeeded()?.value
    #expect(
      model.soundComparisonStatus(sessionID: session.id, takeID: take.id)
        == .notComparable(.takeAudioMissing))

    try FileManager.default.removeItem(at: try #require(session.mimicReference).take.audioURL)
    let other = session.takes[1]
    model.selectTake(other.id)
    #expect(
      model.soundComparisonStatus(sessionID: session.id, takeID: other.id)
        == .notComparable(.referenceAudioMissing))
    #expect(model.compareSoundsIfNeeded() == nil)
    #expect(await service.compareCalls == 1)
  }

  @Test("Experimental engines do not run or show while Experiments hides them")
  func hiddenTierIsInactive() async throws {
    let service = FakeSoundComparison()
    let (model, root, session) = try await makeModel(service)
    defer { try? FileManager.default.removeItem(at: root) }
    model.showsExperimentalSoundEngines = false
    model.selectTake(session.takes[0].id)

    #expect(model.activeSoundEngineID == nil)
    #expect(model.compareSoundsIfNeeded() == nil)
    #expect(
      model.soundComparisonStatus(sessionID: session.id, takeID: session.takes[0].id) == .noEngine)
    #expect(await service.compareCalls == 0)
  }

  @Test("A flag is placed on the take from its sounds, and Listen plays reference, take, reference")
  func flagRowsAndListenSequence() throws {
    func take(_ text: String) -> PracticeSession {
      let words = text.split(separator: " ").enumerated().map {
        TranscriptWord(
          word: String($0.element), start: Double($0.offset) * 0.5,
          end: Double($0.offset) * 0.5 + 0.4)
      }
      return PracticeSession(
        audioURL: URL(fileURLWithPath: "/dev/null"),
        result: AudioAnalyzer().analyze(samples: tone, sampleRate: 16_000),
        transcription: TranscriptionResult(text: text, words: words, localeIdentifier: "en-US"))
    }
    let reference = take("I really think so")
    let attempt = take("I really sink so")
    let result = SoundComparisonResult(
      engineID: "lite", engineVersion: SoundComparisonConfiguration.engineVersion,
      words: [
        WordSoundScore(wordIndex: 1, text: "really", score: 1, eligible: true, flagged: true, flagRank: 2),
        WordSoundScore(wordIndex: 2, text: "think", score: 2, eligible: true, flagged: true, flagRank: 1),
      ],
      phones: [
        SoundPhone(symbol: "θ", wordIndex: 2, start: 1.02, end: 1.1),
        SoundPhone(symbol: "ŋ", wordIndex: 2, start: 1.2, end: 1.35),
      ])

    let rows = SoundFlagRows.make(
      result: result, reference: reference, attempt: attempt,
      comparison: MimicComparison.compare(reference: reference, attempt: attempt))

    #expect(rows.map(\.word) == ["think", "really"])
    #expect(rows[0].takeWordIndex == 2)
    #expect(rows[0].takeRange == 1.02...1.35)
    #expect(rows[1].takeWordIndex == 1)
    let sequence = SoundFlagRows.listenSequence(
      for: rows[0], referenceDuration: 2, takeDuration: 2)
    #expect(sequence.map(\.source) == [.reference, .attempt, .reference])
    #expect(sequence[0].range.lowerBound < 1.0 && sequence[0].range.upperBound > 1.4)
    #expect(sequence[0] == sequence[2])
  }

  private func makeModel(_ service: FakeSoundComparison) async throws
    -> (AppModel, URL, CoachingSession)
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sound-flow-\(UUID())")
    let dependencies = AppDependencies(
      recorder: AudioRecorder(), systemAudioCapture: SystemAudioCapture(),
      sessionStore: try SessionStore(rootURL: root),
      sessionChatResponder: LocalSessionChatResponder(), soundComparison: service)
    let model = AppModel(loadPersistedData: false, dependencies: dependencies)
    model.showsExperimentalSoundEngines = true
    await model.refreshSoundEngines().value
    let sessionID = UUID()
    func take(_ id: UUID = UUID(), url: URL) -> PracticeSession {
      let words = ["clear", "steady", "voice"].enumerated().map {
        TranscriptWord(word: $0.element, start: Double($0.offset) * 0.4, end: Double($0.offset) * 0.4 + 0.3)
      }
      return PracticeSession(
        id: id, audioURL: url, result: AudioAnalyzer().analyze(samples: tone, sampleRate: 16_000),
        transcription: TranscriptionResult(
          text: "clear steady voice", words: words, localeIdentifier: "en-US"))
    }
    let ids = [UUID(), UUID()]
    var session = CoachingSession(
      id: sessionID, name: "Mimic", mode: .mimic, prompt: "", keepsRecordings: true,
      takes: try ids.map { take($0, url: try model.store.recordingURL(sessionID: sessionID, takeID: $0)) })
    session.mimicReference = MimicReference(
      sourceName: "Clip", take: take(url: try model.store.referenceURL(sessionID: sessionID)),
      sourceStart: 0, sourceEnd: 1.2)
    model.sessions = [session]
    #expect(model.persist())
    // The engine is faked, but Review checks that both audio files are there.
    for url in session.takes.map(\.audioURL) + [session.mimicReference!.take.audioURL] {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data([0]).write(to: url)
    }
    model.selectedSessionID = sessionID
    return (model, root, session)
  }

  /// Clean speech-like tone so today's quality rules pass.
  private var tone: [Float] {
    (0..<19_200).map { i in
      let envelope: Float = (i / 1_600) % 4 == 3 ? 0.001 : 0.4
      return envelope * Float(sin(Double(i) * 2 * .pi * 180 / 16_000))
    }
  }
}
