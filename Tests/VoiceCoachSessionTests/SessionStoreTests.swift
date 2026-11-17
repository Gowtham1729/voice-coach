import Foundation
import Testing
import VoiceCoachCore
import VoiceCoachSession

@Suite("Session persistence")
struct SessionStoreTests {
  @Test("Thin index round-trips analysis through per-take documents")
  func thinRoundTrip() throws {
    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let sessionID = UUID()
    let takeID = UUID()
    let take = SessionTestFixtures.take(
      id: takeID,
      audioURL: try store.recordingURL(sessionID: sessionID, takeID: takeID)
    )
    let session = SessionTestFixtures.session(id: sessionID, take: take)

    try store.save([session], analysisTakeIDs: [takeID])
    let loaded = try store.load()
    let libraryData = try Data(contentsOf: root.appendingPathComponent("session-library.json"))
    let libraryText = String(decoding: libraryData, as: UTF8.self)

    #expect(loaded == [session])
    #expect(libraryText.contains("\"result\"") == false)
    #expect(
      FileManager.default.fileExists(
        atPath: store.analysisURL(sessionID: sessionID, takeID: takeID).path))
  }

  @Test("Speech language survives a thin-index save and old indexes remain readable")
  func languagePersistence() throws {
    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let sessionID = UUID()
    let takeID = UUID()
    let take = SessionTestFixtures.take(
      id: takeID, audioURL: try store.recordingURL(sessionID: sessionID, takeID: takeID))
    var session = SessionTestFixtures.session(id: sessionID, take: take)
    session.transcriptionLocaleIdentifier = "ja_JP"
    try store.save([session], analysisTakeIDs: [takeID])
    #expect(try store.load().first?.transcriptionLocaleIdentifier == "ja_JP")

    let libraryURL = root.appendingPathComponent("session-library.json")
    var document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: libraryURL)) as? [String: Any])
    var stored = try #require(document["sessions"] as? [[String: Any]])
    stored[0].removeValue(forKey: "transcriptionLocaleIdentifier")
    document["sessions"] = stored
    try JSONSerialization.data(withJSONObject: document).write(to: libraryURL)
    #expect(try store.load().first?.transcriptionLocaleIdentifier == nil)
  }

  @Test("A saved retry target round-trips through the store")
  func savedTargetRoundTrip() throws {
    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let session = try mimicSessionWithTarget(store: store)
    let takeID = try #require(session.takes.first?.id)

    try store.save([session], analysisTakeIDs: [takeID])
    let loaded = try #require(store.load().first)

    #expect(loaded.takes.first?.savedTarget == session.takes.first?.savedTarget)
    #expect(loaded.takes.first?.savedTarget?.previousTakeID != nil)
    #expect(loaded.takes.first?.savedTarget?.consecutiveCloseTakes == 1)
  }

  @Test("A schema 3 library written without savedTarget loads with no target")
  func libraryWithoutSavedTarget() throws {
    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let session = try mimicSessionWithTarget(store: store)
    let takeID = try #require(session.takes.first?.id)
    try store.save([session], analysisTakeIDs: [takeID])

    let libraryURL = root.appendingPathComponent("session-library.json")
    var document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: libraryURL)) as? [String: Any])
    #expect(document["schemaVersion"] as? Int == 3)
    var stored = try #require(document["sessions"] as? [[String: Any]])
    var takes = try #require(stored[0]["takes"] as? [[String: Any]])
    #expect(takes[0]["savedTarget"] != nil)
    takes[0].removeValue(forKey: "savedTarget")
    stored[0]["takes"] = takes
    document["sessions"] = stored
    try JSONSerialization.data(withJSONObject: document).write(to: libraryURL)

    let loaded = try #require(store.load().first)
    #expect(loaded.takes.count == 1)
    #expect(loaded.takes.first?.savedTarget == nil)
  }

  private func mimicSessionWithTarget(store: SessionStore) throws -> CoachingSession {
    let sessionID = UUID()
    let takeID = UUID()
    let target = TargetFocus(
      referenceWordIndex: 4, word: "important", kind: .pitch, gap: 3.2,
      referenceRange: 1.9...2.15, takeRange: 2.0...2.25, originalGap: 6,
      previousTakeID: UUID(), previousTakeRange: 2.0...2.25, consecutiveCloseTakes: 1)
    let audioURL = try store.recordingURL(sessionID: sessionID, takeID: takeID)
    let take = PracticeSession(
      id: takeID, createdAt: Date(timeIntervalSince1970: 1_700_000_000), audioURL: audioURL,
      result: SessionTestFixtures.analysis(), savedTarget: target)
    return SessionTestFixtures.session(id: sessionID, take: take, mode: .mimic)
  }

  @Test("Metadata-only save leaves an existing analysis document untouched")
  func metadataOnlySave() throws {
    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let sessionID = UUID()
    let takeID = UUID()
    let take = SessionTestFixtures.take(
      id: takeID,
      audioURL: try store.recordingURL(sessionID: sessionID, takeID: takeID)
    )
    var session = SessionTestFixtures.session(id: sessionID, take: take)
    try store.save([session], analysisTakeIDs: [takeID])
    let analysisURL = store.analysisURL(sessionID: sessionID, takeID: takeID)
    let before = try Data(contentsOf: analysisURL)

    session.name = "Renamed"
    try store.save([session], analysisTakeIDs: [])

    #expect(try Data(contentsOf: analysisURL) == before)
    #expect(try store.load().first?.name == "Renamed")
  }

  @Test("Saving prunes orphan analysis files only after the index commit")
  func orphanPruning() throws {
    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let sessionID = UUID()
    let takeID = UUID()
    let take = SessionTestFixtures.take(
      id: takeID,
      audioURL: try store.recordingURL(sessionID: sessionID, takeID: takeID)
    )
    let session = SessionTestFixtures.session(id: sessionID, take: take)
    try store.save([session], analysisTakeIDs: [takeID])
    let orphanURL = store.analysisURL(sessionID: sessionID, takeID: UUID())
    try Data("orphan".utf8).write(to: orphanURL)

    try store.save([session], analysisTakeIDs: [])

    #expect(FileManager.default.fileExists(atPath: orphanURL.path) == false)
  }

  @Test("Orphan cleanup failure cannot invalidate an already committed library")
  func cleanupFailureAfterCommit() throws {
    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let sessionID = UUID()
    let takeID = UUID()
    let take = SessionTestFixtures.take(
      id: takeID, audioURL: try store.recordingURL(sessionID: sessionID, takeID: takeID))
    var session = SessionTestFixtures.session(id: sessionID, take: take)
    try store.save([session], analysisTakeIDs: [takeID])
    let orphan = store.analysisURL(sessionID: sessionID, takeID: UUID())
    try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: false)
    try Data("locked orphan".utf8).write(to: orphan.appendingPathComponent("child"))
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: orphan.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: orphan.path)
    }
    session.name = "Committed"

    try store.save([session], analysisTakeIDs: [])

    #expect(try store.load() == [session])
    #expect(FileManager.default.fileExists(atPath: store.analysisURL(sessionID: sessionID, takeID: takeID).path))
  }

  @Test("Version two libraries migrate once and keep a backup")
  func legacyMigration() throws {
    struct LegacyDocument: Codable {
      let schemaVersion: Int
      let sessions: [CoachingSession]
    }

    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let sessionID = UUID()
    let takeID = UUID()
    let take = SessionTestFixtures.take(
      id: takeID,
      audioURL: try store.recordingURL(sessionID: sessionID, takeID: takeID)
    )
    let session = SessionTestFixtures.session(id: sessionID, take: take)
    let libraryURL = root.appendingPathComponent("session-library.json")
    try JSONEncoder().encode(LegacyDocument(schemaVersion: 2, sessions: [session]))
      .write(to: libraryURL)

    #expect(try store.load() == [session])
    #expect(
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent("session-library-v2-backup.json").path
      ))
    #expect(
      FileManager.default.fileExists(
        atPath: store.analysisURL(sessionID: sessionID, takeID: takeID).path))
  }

  @Test("Orphan sweep removes only unindexed staging folders and never take audio")
  func orphanSweep() throws {
    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let sessionID = UUID()
    let takeID = UUID()
    let take = SessionTestFixtures.take(
      id: takeID, audioURL: try store.recordingURL(sessionID: sessionID, takeID: takeID))
    try store.save([SessionTestFixtures.session(id: sessionID, take: take)], analysisTakeIDs: [takeID])

    let orphan = UUID()
    try Data("wav".utf8).write(to: store.referenceURL(sessionID: orphan))
    let analysed = UUID()
    _ = try store.takeDirectory(sessionID: analysed)
    try Data("{}".utf8).write(to: store.analysisURL(sessionID: analysed, takeID: UUID()))
    let audioOnly = UUID()
    try Data("wav".utf8).write(to: store.recordingURL(sessionID: audioOnly, takeID: UUID()))
    let sessions = root.appendingPathComponent("Sessions", isDirectory: true)
    let named = sessions.appendingPathComponent("not-a-uuid", isDirectory: true)
    try FileManager.default.createDirectory(at: named, withIntermediateDirectories: true)

    let removed = try store.removeOrphanedSessionDirectories(knownSessionIDs: [sessionID])
    let exists = { (url: URL) in FileManager.default.fileExists(atPath: url.path) }
    #expect(removed == 1)
    #expect(!exists(sessions.appendingPathComponent(orphan.uuidString)))
    #expect(exists(sessions.appendingPathComponent(sessionID.uuidString)))
    #expect(exists(sessions.appendingPathComponent(analysed.uuidString)))
    #expect(exists(sessions.appendingPathComponent(audioOnly.uuidString)))
    #expect(exists(named))
    #expect(try store.load().count == 1)
  }

  // MARK: - Resilient load

  private func practiceTake(_ store: SessionStore, sessionID: UUID, offset: Double)
    throws -> PracticeSession
  {
    let id = UUID()
    return PracticeSession(
      id: id, createdAt: Date(timeIntervalSince1970: 1_700_000_000 + offset),
      audioURL: try store.recordingURL(sessionID: sessionID, takeID: id),
      result: SessionTestFixtures.analysis())
  }

  private func libraryText(_ root: URL) throws -> String {
    String(
      decoding: try Data(contentsOf: root.appendingPathComponent("session-library.json")),
      as: UTF8.self)
  }

  @Test("A missing analysis file skips only that take and survives the next save")
  func missingAnalysisSkipsOnlyThatTake() throws {
    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let sessionID = UUID()
    let first = try practiceTake(store, sessionID: sessionID, offset: 0)
    let second = try practiceTake(store, sessionID: sessionID, offset: 10)
    var session = SessionTestFixtures.session(id: sessionID, take: first)
    session.takes = [first, second]
    let other = SessionTestFixtures.session(
      take: try practiceTake(store, sessionID: UUID(), offset: 0))
    try store.save([session, other])

    let lostURL = store.analysisURL(sessionID: sessionID, takeID: first.id)
    let lostData = try Data(contentsOf: lostURL)
    try FileManager.default.removeItem(at: lostURL)
    let loaded = try store.load()
    #expect(store.lastLoadSkippedTakeCount == 1)
    #expect(loaded.count == 2)
    #expect(loaded.first { $0.id == sessionID }?.takes.map(\.id) == [second.id])

    try store.save(loaded)
    #expect(try libraryText(root).contains(first.id.uuidString))

    // Restoring the file brings the take back.
    try lostData.write(to: lostURL)
    let restored = try store.load()
    #expect(store.lastLoadSkippedTakeCount == 0)
    #expect(restored.first { $0.id == sessionID }?.takes.map(\.id) == [first.id, second.id])
  }

  @Test("An unreadable Mimic reference skips only that session and keeps its files")
  func corruptReferenceSkipsSession() throws {
    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let mimicID = UUID()
    let attempt = try practiceTake(store, sessionID: mimicID, offset: 5)
    let reference = try practiceTake(store, sessionID: mimicID, offset: 0)
    let mimic = CoachingSession(
      id: mimicID, name: "Mimic", mode: .mimic, prompt: "", keepsRecordings: true,
      takes: [attempt],
      mimicReference: MimicReference(
        sourceName: "clip", take: reference, sourceStart: 0, sourceEnd: 2))
    let plainID = UUID()
    let plain = SessionTestFixtures.session(
      id: plainID, take: try practiceTake(store, sessionID: plainID, offset: 0))
    try store.save([mimic, plain])

    let referenceAnalysis = store.analysisURL(sessionID: mimicID, takeID: reference.id)
    try Data("not json".utf8).write(to: referenceAnalysis)
    let loaded = try store.load()
    #expect(loaded.map(\.id) == [plain.id])
    #expect(store.lastLoadSkippedTakeCount > 0)

    try store.save(loaded)
    #expect(try libraryText(root).contains(mimicID.uuidString))
    #expect(FileManager.default.fileExists(atPath: referenceAnalysis.path))
    #expect(
      FileManager.default.fileExists(
        atPath: store.analysisURL(sessionID: mimicID, takeID: attempt.id).path))
    let removed = try store.removeOrphanedSessionDirectories(knownSessionIDs: [plain.id])
    #expect(removed == 0)
  }

  @Test("Loading creates no directories")
  func loadCreatesNoDirectories() throws {
    let root = try SessionTestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(rootURL: root)
    let sessionID = UUID()
    let take = try practiceTake(store, sessionID: sessionID, offset: 0)
    try store.save([SessionTestFixtures.session(id: sessionID, take: take)])
    try FileManager.default.removeItem(
      at: root.appendingPathComponent("Sessions", isDirectory: true)
        .appendingPathComponent(sessionID.uuidString))

    #expect(try store.load().isEmpty)
    #expect(
      !FileManager.default.fileExists(
        atPath: root.appendingPathComponent("Sessions/\(sessionID.uuidString)").path))
  }
}
