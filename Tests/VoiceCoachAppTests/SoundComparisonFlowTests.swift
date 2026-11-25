import Foundation
import Testing
import VoiceCoachCore
import VoiceCoachSession

@testable import VoiceCoachApp

private actor FakeSoundComparison: SoundComparing {
  var referenceCalls = 0
  var compareCalls = 0
  let fails: Bool

  init(fails: Bool = false) { self.fails = fails }

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

  func compare(engineID: String, reference: ReferenceAnalysis, takeAudioURL: URL) throws
    -> SoundComparisonResult
  {
    compareCalls += 1
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
