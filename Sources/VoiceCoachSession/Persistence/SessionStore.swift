import Foundation
import VoiceCoachCore

package protocol SessionStoring: AnyObject {
  var rootURL: URL { get }
  /// Takes (or whole sessions) the last `load()` could not read and left on disk untouched.
  var lastLoadSkippedTakeCount: Int { get }

  func load() throws -> [CoachingSession]
  func save(_ sessions: [CoachingSession], analysisTakeIDs: Set<UUID>?) throws
  func recordingURL(sessionID: UUID, takeID: UUID) throws -> URL
  func importedAudioURL(sessionID: UUID, takeID: UUID, fileExtension: String) throws -> URL
  func referenceURL(sessionID: UUID) throws -> URL
  func analysisURL(sessionID: UUID, takeID: UUID) -> URL
  func takeDirectory(sessionID: UUID) throws -> URL
  func deleteSessionData(sessionID: UUID) throws
  func deleteTakeAnalysis(sessionID: UUID, takeID: UUID) throws
  func removeOrphanedSessionDirectories(knownSessionIDs: Set<UUID>) throws -> Int
}

/// On-disk library index. Heavy analysis lives in per-take `*.analysis.json` files.
package struct ThinLibraryDocument: Codable {
  package let schemaVersion: Int
  package let sessions: [StoredSession]

  package init(schemaVersion: Int, sessions: [StoredSession]) {
    self.schemaVersion = schemaVersion
    self.sessions = sessions
  }
}

package struct FatLibraryDocument: Codable {
  package let schemaVersion: Int
  package let sessions: [CoachingSession]

  package init(schemaVersion: Int, sessions: [CoachingSession]) {
    self.schemaVersion = schemaVersion
    self.sessions = sessions
  }
}

package struct StoredSession: Codable {
  package let id: UUID
  package var name: String
  package let createdAt: Date
  package var updatedAt: Date
  package var mode: PracticeMode
  package var prompt: String
  package var keepsRecordings: Bool
  package var takes: [StoredTake]
  package var mimicReference: StoredMimicReference?
  package var mimicStyle: MimicStyle?
  package var mimicAttemptStyles: [UUID: MimicStyle]?
  package var archived: Bool?
  package var transcriptionLocaleIdentifier: String?

  package init(
    id: UUID,
    name: String,
    createdAt: Date,
    updatedAt: Date,
    mode: PracticeMode,
    prompt: String,
    keepsRecordings: Bool,
    takes: [StoredTake],
    mimicReference: StoredMimicReference? = nil,
    mimicStyle: MimicStyle? = nil,
    mimicAttemptStyles: [UUID: MimicStyle]? = nil,
    archived: Bool? = nil,
    transcriptionLocaleIdentifier: String? = nil
  ) {
    self.id = id
    self.name = name
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.mode = mode
    self.prompt = prompt
    self.keepsRecordings = keepsRecordings
    self.takes = takes
    self.mimicReference = mimicReference
    self.mimicStyle = mimicStyle
    self.mimicAttemptStyles = mimicAttemptStyles
    self.archived = archived
    self.transcriptionLocaleIdentifier = transcriptionLocaleIdentifier
  }
}

package struct StoredTake: Codable, Equatable {
  package let id: UUID
  package let createdAt: Date
  package let audioFileName: String
  package let source: TakeSource?
  package var savedTarget: TargetFocus?

  package init(
    id: UUID,
    createdAt: Date,
    audioFileName: String,
    source: TakeSource? = nil,
    savedTarget: TargetFocus? = nil
  ) {
    self.id = id
    self.createdAt = createdAt
    self.audioFileName = audioFileName
    self.source = source
    self.savedTarget = savedTarget
  }
}

package struct StoredMimicReference: Codable {
  package var sourceName: String
  package var sourceStart: Double
  package var sourceEnd: Double
  package var take: StoredTake

  package init(
    sourceName: String,
    sourceStart: Double,
    sourceEnd: Double,
    take: StoredTake
  ) {
    self.sourceName = sourceName
    self.sourceStart = sourceStart
    self.sourceEnd = sourceEnd
    self.take = take
  }
}

/// Per-take analysis file. `sounds` is optional and additive: schemaVersion stays 1, so builds
/// without Sound comparison still read (and ignore) it, and files without it load unchanged.
private struct TakeAnalysisDocument: Codable {
  let schemaVersion: Int
  let result: AnalysisResult
  let transcription: TranscriptionResult?
  let words: [WordAnalysis]
  let sounds: TakeSounds?
}

package final class SessionStore: SessionStoring {
  package static let currentSchemaVersion = 3
  package static let analysisSchemaVersion = 1

  package let rootURL: URL
  private let libraryURL: URL
  package private(set) var lastLoadSkippedTakeCount = 0
  /// Index stubs for takes whose analysis could not be read. Written back on save so a
  /// restored file reappears, and excluded from pruning.
  private var skippedTakeStubs: [UUID: [StoredTake]] = [:]
  /// Index stubs for sessions skipped whole (unreadable Mimic reference, or no readable takes).
  private var skippedSessionStubs: [UUID: StoredSession] = [:]

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
    lastLoadSkippedTakeCount = 0
    skippedTakeStubs = [:]
    skippedSessionStubs = [:]
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
      return document.sessions
        .compactMap(hydrateSkippingUnreadable(session:))
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

    let liveIDs = Set(sessions.map(\.id))
    let document = ThinLibraryDocument(
      schemaVersion: Self.currentSchemaVersion,
      sessions: sessions.map(makeStoredSessionKeepingSkipped(_:))
        + skippedSessionStubs.values.filter { !liveIDs.contains($0.id) }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(document).write(to: libraryURL, options: .atomic)

    // Prune only after the index commit. Cleanup is best effort: reporting a
    // failed save after the commit would make callers roll back and delete audio
    // that the on-disk index now references. A later save retries orphan cleanup.
    for session in sessions {
      let skipped = Set((skippedTakeStubs[session.id] ?? []).map(\.id))
      try? pruneAnalyses(
        sessionID: session.id, keeping: Set(session.allPracticeTakes.map(\.id)).union(skipped))
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
    let directory = sessionDirectoryURL(sessionID: sessionID)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  package func deleteSessionData(sessionID: UUID) throws {
    let directory = sessionDirectoryURL(sessionID: sessionID)
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    try FileManager.default.removeItem(at: directory)
  }

  /// Removes never-indexed staging leftovers, such as folders from a crash mid-batch.
  /// Only UUID-named folders outside `knownSessionIDs` that are empty or hold nothing
  /// but a staged `reference.wav` qualify. A folder with any take audio or analysis is
  /// left alone: it may be a recording the index lost, and that must stay recoverable.
  @discardableResult
  package func removeOrphanedSessionDirectories(knownSessionIDs: Set<UUID>) throws -> Int {
    let sessionsURL = rootURL.appendingPathComponent("Sessions", isDirectory: true)
    guard FileManager.default.fileExists(atPath: sessionsURL.path) else { return 0 }
    var removed = 0
    for directory in try FileManager.default.contentsOfDirectory(
      at: sessionsURL, includingPropertiesForKeys: [.isDirectoryKey])
    {
      guard let id = UUID(uuidString: directory.lastPathComponent),
        !knownSessionIDs.contains(id),
        skippedSessionStubs[id] == nil,
        (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
        let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path),
        files.allSatisfy({ $0 == "reference.wav" || $0 == ".DS_Store" })
      else { continue }
      try FileManager.default.removeItem(at: directory)
      removed += 1
    }
    return removed
  }

  package func deleteTakeAnalysis(sessionID: UUID, takeID: UUID) throws {
    let url = analysisURL(sessionID: sessionID, takeID: takeID)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }

  // MARK: - Private

  private func sessionDirectoryURL(sessionID: UUID) -> URL {
    rootURL
      .appendingPathComponent("Sessions", isDirectory: true)
      .appendingPathComponent(sessionID.uuidString, isDirectory: true)
  }

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
      archived: session.archived ? true : nil,
      transcriptionLocaleIdentifier: session.transcriptionLocaleIdentifier
    )
  }

  private func makeStoredTake(_ take: PracticeSession) -> StoredTake {
    StoredTake(
      id: take.id,
      createdAt: take.createdAt,
      audioFileName: take.audioURL.lastPathComponent,
      source: take.source,
      savedTarget: take.savedTarget
    )
  }

  /// Skips what cannot be read instead of failing the whole library. Nothing is deleted.
  private func hydrateSkippingUnreadable(session stored: StoredSession) -> CoachingSession? {
    var takes: [PracticeSession] = []
    var skipped: [StoredTake] = []
    for take in stored.takes {
      if let hydrated = try? hydrate(take: take, sessionID: stored.id) {
        takes.append(hydrated)
      } else {
        skipped.append(take)
      }
    }
    var reference: MimicReference?
    if let storedReference = stored.mimicReference {
      guard let take = try? hydrate(take: storedReference.take, sessionID: stored.id) else {
        return skipWhole(stored, count: 1 + stored.takes.count)
      }
      reference = MimicReference(
        sourceName: storedReference.sourceName,
        take: take,
        sourceStart: storedReference.sourceStart,
        sourceEnd: storedReference.sourceEnd
      )
    } else if takes.isEmpty && !skipped.isEmpty {
      return skipWhole(stored, count: skipped.count)
    }
    if !skipped.isEmpty {
      skippedTakeStubs[stored.id] = skipped
      lastLoadSkippedTakeCount += skipped.count
    }
    return CoachingSession(
      id: stored.id,
      name: stored.name,
      createdAt: stored.createdAt,
      updatedAt: stored.updatedAt,
      mode: stored.mode,
      prompt: stored.prompt,
      keepsRecordings: stored.keepsRecordings,
      takes: takes,
      mimicReference: reference,
      mimicStyle: stored.mimicStyle,
      mimicAttemptStyles: stored.mimicAttemptStyles,
      transcriptionLocaleIdentifier: stored.transcriptionLocaleIdentifier,
      archived: stored.archived ?? false
    )
  }

  private func skipWhole(_ stored: StoredSession, count: Int) -> CoachingSession? {
    skippedSessionStubs[stored.id] = stored
    lastLoadSkippedTakeCount += count
    return nil
  }

  private func makeStoredSessionKeepingSkipped(_ session: CoachingSession) -> StoredSession {
    var stored = makeStoredSession(session)
    if let skipped = skippedTakeStubs[session.id], !skipped.isEmpty {
      stored.takes = (stored.takes + skipped).sorted { $0.createdAt < $1.createdAt }
    }
    return stored
  }

  private func hydrate(take stored: StoredTake, sessionID: UUID) throws -> PracticeSession {
    let analysis = try loadAnalysis(sessionID: sessionID, takeID: stored.id)
    return PracticeSession(
      id: stored.id,
      createdAt: stored.createdAt,
      audioURL: sessionDirectoryURL(sessionID: sessionID).appendingPathComponent(
        stored.audioFileName),
      source: stored.source,
      result: analysis.result,
      transcription: analysis.transcription,
      words: analysis.words,
      savedTarget: stored.savedTarget,
      sounds: analysis.sounds
    )
  }

  private func writeAnalysis(sessionID: UUID, take: PracticeSession) throws {
    let document = TakeAnalysisDocument(
      schemaVersion: Self.analysisSchemaVersion,
      result: take.result,
      transcription: take.transcription,
      words: take.words,
      sounds: take.sounds
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
    let directory = sessionDirectoryURL(sessionID: sessionID)
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    let files = try FileManager.default.contentsOfDirectory(
      at: directory,
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
