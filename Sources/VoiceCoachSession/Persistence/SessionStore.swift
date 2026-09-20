import Foundation
import VoiceCoachCore

package protocol SessionStoring: AnyObject {
  var rootURL: URL { get }

  func load() throws -> [CoachingSession]
  func save(_ sessions: [CoachingSession], analysisTakeIDs: Set<UUID>?) throws
  func recordingURL(sessionID: UUID, takeID: UUID) throws -> URL
  func importedAudioURL(sessionID: UUID, takeID: UUID, fileExtension: String) throws -> URL
  func referenceURL(sessionID: UUID) throws -> URL
  func analysisURL(sessionID: UUID, takeID: UUID) -> URL
  func takeDirectory(sessionID: UUID) throws -> URL
  func deleteSessionData(sessionID: UUID) throws
  func deleteTakeAnalysis(sessionID: UUID, takeID: UUID) throws
}

/// On-disk library index. Heavy analysis lives in per-take `*.analysis.json` files.
private struct ThinLibraryDocument: Codable {
  let schemaVersion: Int
  let sessions: [StoredSession]
}

private struct FatLibraryDocument: Codable {
  let schemaVersion: Int
  let sessions: [CoachingSession]
}

private struct StoredSession: Codable {
  let id: UUID
  var name: String
  let createdAt: Date
  var updatedAt: Date
  var mode: PracticeMode
  var prompt: String
  var keepsRecordings: Bool
  var takes: [StoredTake]
  var mimicReference: StoredMimicReference?
  var mimicStyle: MimicStyle?
  var mimicAttemptStyles: [UUID: MimicStyle]?
  var archived: Bool?
}

private struct StoredTake: Codable {
  let id: UUID
  let createdAt: Date
  let audioFileName: String
  let source: TakeSource?
}

private struct StoredMimicReference: Codable {
  var sourceName: String
  var sourceStart: Double
  var sourceEnd: Double
  var take: StoredTake
}

private struct TakeAnalysisDocument: Codable {
  let schemaVersion: Int
  let result: AnalysisResult
  let transcription: TranscriptionResult?
  let words: [WordAnalysis]
}

package final class SessionStore: SessionStoring {
  package static let currentSchemaVersion = 3
  package static let analysisSchemaVersion = 1

  package let rootURL: URL
  private let libraryURL: URL

  package init(rootURL: URL? = nil) throws {
    if let rootURL {
      self.rootURL = rootURL
    } else {
      let applicationSupport = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      self.rootURL = applicationSupport.appendingPathComponent("VoiceCoach", isDirectory: true)
    }
    libraryURL = self.rootURL.appendingPathComponent("session-library.json")
    try FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
  }

  package func load() throws -> [CoachingSession] {
    guard FileManager.default.fileExists(atPath: libraryURL.path) else { return [] }
    let data = try Data(contentsOf: libraryURL)
    let version = try Self.peekSchemaVersion(in: data)

    switch version {
    case 1, 2:
      let document = try JSONDecoder().decode(FatLibraryDocument.self, from: data)
      let sessions = document.sessions.sorted { $0.updatedAt > $1.updatedAt }
      try migrateFatLibrary(sessions, priorData: data, priorVersion: version)
      return sessions
    case 3:
      let document = try JSONDecoder().decode(ThinLibraryDocument.self, from: data)
      return try document.sessions
        .map(hydrate(session:))
        .sorted { $0.updatedAt > $1.updatedAt }
    default:
      throw CocoaError(.coderReadCorrupt)
    }
  }

  /// Persists the thin session index. Pass take IDs to rewrite those analysis blobs;
  /// `nil` rewrites every take; `[]` is index-only (still writes any missing blobs).
  package func save(_ sessions: [CoachingSession], analysisTakeIDs: Set<UUID>? = nil) throws {
    for session in sessions {
      _ = try takeDirectory(sessionID: session.id)
      for take in analysisTargets(in: session, analysisTakeIDs: analysisTakeIDs) {
        try writeAnalysis(sessionID: session.id, take: take)
      }
    }

    let document = ThinLibraryDocument(
      schemaVersion: Self.currentSchemaVersion,
      sessions: sessions.map(makeStoredSession(_:))
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(document).write(to: libraryURL, options: .atomic)

    // Prune only after the index commit so a failed write cannot leave
    // the on-disk index pointing at deleted analysis blobs.
    for session in sessions {
      try pruneAnalyses(sessionID: session.id, keeping: Set(session.allPracticeTakes.map(\.id)))
    }
  }

  package func recordingURL(sessionID: UUID, takeID: UUID) throws -> URL {
    try takeDirectory(sessionID: sessionID)
      .appendingPathComponent("take-\(takeID.uuidString).wav")
  }

  package func importedAudioURL(sessionID: UUID, takeID: UUID, fileExtension: String) throws -> URL
  {
    let normalizedExtension = fileExtension.isEmpty ? "wav" : fileExtension.lowercased()
    return try takeDirectory(sessionID: sessionID)
      .appendingPathComponent("take-\(takeID.uuidString)-imported.\(normalizedExtension)")
  }

  package func referenceURL(sessionID: UUID) throws -> URL {
    try takeDirectory(sessionID: sessionID).appendingPathComponent("reference.wav")
  }

  package func analysisURL(sessionID: UUID, takeID: UUID) -> URL {
    rootURL
      .appendingPathComponent("Sessions", isDirectory: true)
      .appendingPathComponent(sessionID.uuidString, isDirectory: true)
      .appendingPathComponent("take-\(takeID.uuidString).analysis.json")
  }

  package func takeDirectory(sessionID: UUID) throws -> URL {
    let directory =
      rootURL
      .appendingPathComponent("Sessions", isDirectory: true)
      .appendingPathComponent(sessionID.uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  package func deleteSessionData(sessionID: UUID) throws {
    let directory =
      rootURL
      .appendingPathComponent("Sessions", isDirectory: true)
      .appendingPathComponent(sessionID.uuidString, isDirectory: true)
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    try FileManager.default.removeItem(at: directory)
  }

  package func deleteTakeAnalysis(sessionID: UUID, takeID: UUID) throws {
    let url = analysisURL(sessionID: sessionID, takeID: takeID)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }

  // MARK: - Private

  private static func peekSchemaVersion(in data: Data) throws -> Int {
    let json = try JSONSerialization.jsonObject(with: data)
    guard let object = json as? [String: Any], let version = object["schemaVersion"] as? Int else {
      throw CocoaError(.coderReadCorrupt)
    }
    return version
  }

  private func migrateFatLibrary(_ sessions: [CoachingSession], priorData: Data, priorVersion: Int)
    throws
  {
    let backupName =
      priorVersion == 1
      ? "session-library-v1-backup.json"
      : "session-library-v2-backup.json"
    let backup = rootURL.appendingPathComponent(backupName)
    if !FileManager.default.fileExists(atPath: backup.path) {
      try priorData.write(to: backup, options: .atomic)
    }
    try save(sessions, analysisTakeIDs: nil)
  }

  private func analysisTargets(in session: CoachingSession, analysisTakeIDs: Set<UUID>?)
    -> [PracticeSession]
  {
    guard let analysisTakeIDs else { return session.allPracticeTakes }
    return session.allPracticeTakes.filter { take in
      analysisTakeIDs.contains(take.id)
        || !FileManager.default.fileExists(
          atPath: analysisURL(sessionID: session.id, takeID: take.id).path)
    }
  }

  private func makeStoredSession(_ session: CoachingSession) -> StoredSession {
    StoredSession(
      id: session.id,
      name: session.name,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      mode: session.mode,
      prompt: session.prompt,
      keepsRecordings: session.keepsRecordings,
      takes: session.takes.map(makeStoredTake(_:)),
      mimicReference: session.mimicReference.map { reference in
        StoredMimicReference(
          sourceName: reference.sourceName,
          sourceStart: reference.sourceStart,
          sourceEnd: reference.sourceEnd,
          take: makeStoredTake(reference.take)
        )
      },
      mimicStyle: session.mimicStyle,
      mimicAttemptStyles: session.mimicAttemptStyles,
      archived: session.archived ? true : nil
    )
  }

  private func makeStoredTake(_ take: PracticeSession) -> StoredTake {
    StoredTake(
      id: take.id,
      createdAt: take.createdAt,
      audioFileName: take.audioURL.lastPathComponent,
      source: take.source
    )
  }

  private func hydrate(session stored: StoredSession) throws -> CoachingSession {
    CoachingSession(
      id: stored.id,
      name: stored.name,
      createdAt: stored.createdAt,
      updatedAt: stored.updatedAt,
      mode: stored.mode,
      prompt: stored.prompt,
      keepsRecordings: stored.keepsRecordings,
      takes: try stored.takes.map { try hydrate(take: $0, sessionID: stored.id) },
      mimicReference: try stored.mimicReference.map { reference in
        MimicReference(
          sourceName: reference.sourceName,
          take: try hydrate(take: reference.take, sessionID: stored.id),
          sourceStart: reference.sourceStart,
          sourceEnd: reference.sourceEnd
        )
      },
      mimicStyle: stored.mimicStyle,
      mimicAttemptStyles: stored.mimicAttemptStyles,
      archived: stored.archived ?? false
    )
  }

  private func hydrate(take stored: StoredTake, sessionID: UUID) throws -> PracticeSession {
    let analysis = try loadAnalysis(sessionID: sessionID, takeID: stored.id)
    return PracticeSession(
      id: stored.id,
      createdAt: stored.createdAt,
      audioURL: try takeDirectory(sessionID: sessionID).appendingPathComponent(
        stored.audioFileName),
      source: stored.source,
      result: analysis.result,
      transcription: analysis.transcription,
      words: analysis.words
    )
  }

  private func writeAnalysis(sessionID: UUID, take: PracticeSession) throws {
    let document = TakeAnalysisDocument(
      schemaVersion: Self.analysisSchemaVersion,
      result: take.result,
      transcription: take.transcription,
      words: take.words
    )
    try JSONEncoder().encode(document).write(
      to: analysisURL(sessionID: sessionID, takeID: take.id),
      options: .atomic
    )
  }

  private func loadAnalysis(sessionID: UUID, takeID: UUID) throws -> TakeAnalysisDocument {
    let document = try JSONDecoder().decode(
      TakeAnalysisDocument.self,
      from: Data(contentsOf: analysisURL(sessionID: sessionID, takeID: takeID))
    )
    guard document.schemaVersion == Self.analysisSchemaVersion else {
      throw CocoaError(.coderReadCorrupt)
    }
    return document
  }

  private func pruneAnalyses(sessionID: UUID, keeping: Set<UUID>) throws {
    let files = try FileManager.default.contentsOfDirectory(
      at: try takeDirectory(sessionID: sessionID),
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    for file in files {
      guard let takeID = Self.takeID(fromAnalysisFileName: file.lastPathComponent),
        !keeping.contains(takeID)
      else { continue }
      try FileManager.default.removeItem(at: file)
    }
  }

  private static func takeID(fromAnalysisFileName name: String) -> UUID? {
    // take-<uuid>.analysis.json
    guard name.hasPrefix("take-"), name.hasSuffix(".analysis.json") else { return nil }
    let idString = String(name.dropFirst("take-".count).dropLast(".analysis.json".count))
    return UUID(uuidString: idString)
  }
}
