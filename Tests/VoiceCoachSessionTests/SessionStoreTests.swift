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
}
