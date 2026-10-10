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
}
