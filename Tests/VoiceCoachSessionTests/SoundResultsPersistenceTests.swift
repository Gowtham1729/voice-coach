import Foundation
import Testing
import VoiceCoachCore
import VoiceCoachSession

@Suite("Sound result persistence")
struct SoundResultsPersistenceTests {
  private func result(_ engineID: String) -> SoundComparisonResult {
    SoundComparisonResult(
      engineID: engineID, engineVersion: SoundComparisonConfiguration.engineVersion,
      words: [
        WordSoundScore(
          wordIndex: 0, text: "ship", score: 20, eligible: true, flagged: true, flagRank: 1)
      ],
      phones: [SoundPhone(symbol: "ʃ", wordIndex: 0, start: 0.1, end: 0.2)])
  }

  /// A Mimic practice whose take has lite and full results and whose Reference caches both.
  private func mimic(store: SessionStore) throws -> CoachingSession {
    let sessionID = UUID()
    let takeID = UUID()
    let referenceID = UUID()
    let take = SessionTestFixtures.take(
      id: takeID, audioURL: try store.recordingURL(sessionID: sessionID, takeID: takeID)
    ).replacingSounds(TakeSounds(comparisons: ["lite": result("lite"), "full": result("full")]))
    let analyses = ["lite", "full"].map {
      ReferenceAnalysis(
        engineID: $0, engineVersion: SoundComparisonConfiguration.engineVersion,
        words: [SoundWord(text: "ship", start: 0.1, end: 0.4)], models: [])
    }
    let reference = SessionTestFixtures.take(
      id: referenceID, audioURL: try store.referenceURL(sessionID: sessionID)
    ).replacingSounds(TakeSounds(referenceAnalyses: ["lite": analyses[0], "full": analyses[1]]))
    var session = SessionTestFixtures.session(id: sessionID, take: take, mode: .mimic)
    session.mimicReference = MimicReference(
      sourceName: "Clip", take: reference, sourceStart: 0, sourceEnd: 2)
    return session
  }

  @Test("Sound results round-trip in the take analysis file; the index stays schema 3")
  func roundTrip() throws {
    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let session = try mimic(store: store)

    try store.save([session])
    #expect(try store.load() == [session])
    let index = try String(
      contentsOf: root.appendingPathComponent("session-library.json"), encoding: .utf8)
    #expect(index.contains("\"schemaVersion\":3"))
    #expect(!index.contains("comparisons"))
  }

  /// PS-4 and PS-5: files without `sounds` load as before, and new files still decode with the
  /// analysis document of builds that predate Sound comparison (schemaVersion 1, same keys).
  @Test("Old analysis files load, and new ones stay readable by older builds")
  func compatibility() throws {
    struct ReleasedAnalysisDocument: Decodable {
      let schemaVersion: Int
      let result: AnalysisResult
      let transcription: TranscriptionResult?
      let words: [WordAnalysis]
    }
    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let session = try mimic(store: store)
    try store.save([session])
    let take = session.takes[0]
    let url = store.analysisURL(sessionID: session.id, takeID: take.id)

    let released = try JSONDecoder().decode(
      ReleasedAnalysisDocument.self, from: Data(contentsOf: url))
    #expect(released.schemaVersion == 1)
    #expect(released.result == take.result)

    // What a released build writes: the same document without `sounds`.
    var object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect(object.removeValue(forKey: "sounds") != nil)
    try JSONSerialization.data(withJSONObject: object).write(to: url)
    let loaded = try #require(try store.load().first?.takes.first)
    #expect(loaded.sounds == nil)
    #expect(loaded.replacingSounds(take.sounds) == take)
  }

  @Test("Deleting an engine removes every result it made and nothing else")
  func engineDeleteCleanup() throws {
    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    var session = try mimic(store: store)
    try store.save([session])

    let changed = session.removeSoundResults(engineID: "lite")
    #expect(changed == [session.takes[0].id, session.mimicReference!.take.id])
    try store.save([session], analysisTakeIDs: changed)

    let loaded = try #require(try store.load().first)
    #expect(loaded.takes[0].sounds?.comparisons.keys.sorted() == ["full"])
    #expect(loaded.mimicReference?.take.sounds?.referenceAnalyses.keys.sorted() == ["full"])
    #expect(loaded.takes[0].result == session.takes[0].result)
    #expect(loaded.removeSoundResultsCopy("full").allSatisfy { $0.sounds == nil })
  }
}

extension CoachingSession {
  fileprivate func removeSoundResultsCopy(_ engineID: String) -> [PracticeSession] {
    var copy = self
    _ = copy.removeSoundResults(engineID: engineID)
    return copy.takes + [copy.mimicReference!.take]
  }
}
