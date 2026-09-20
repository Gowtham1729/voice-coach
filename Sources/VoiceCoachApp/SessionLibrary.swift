import Foundation
import VoiceCoachCore

enum PracticeMode: String, Codable, CaseIterable, Identifiable {
    case general
    case prompt
    case freeSpeaking
    case mimic

    // Keep legacy cases decodable for existing libraries, but new capture is Record or Mimic.
    static var allCases: [PracticeMode] { [.general, .mimic] }

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General practice"
        case .prompt: "Read a prompt"
        case .freeSpeaking: "Free speaking"
        case .mimic: "Mimic a reference"
        }
    }

    var detail: String {
        switch self {
        case .general: "Speak freely on any topic. Build consistency and confidence."
        case .prompt: "Read a short prompt aloud. Focus on clarity and delivery."
        case .freeSpeaking: "Speak on a topic of your choice. Develop structure and fluency."
        case .mimic: "Listen, imitate a short clip, compare, and retry."
        }
    }

    var icon: String {
        switch self {
        case .general: "mic.fill"
        case .prompt: "doc.text.fill"
        case .freeSpeaking: "chart.bar.fill"
        case .mimic: "waveform.path"
        }
    }
}

enum MimicStyle: String, Codable, CaseIterable, Identifiable {
    case listenAndRepeat
    case speakAlong

    var id: Self { self }
    var title: String {
        switch self {
        case .listenAndRepeat: "Listen & Repeat"
        case .speakAlong: "Speak Along"
        }
    }
}

struct MimicReference: Codable, Equatable {
    var sourceName: String
    var take: PracticeSession
    var sourceStart: Double
    var sourceEnd: Double
}

struct CoachingSession: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var mode: PracticeMode
    var prompt: String
    var keepsRecordings: Bool
    var takes: [PracticeSession]
    var mimicReference: MimicReference?
    var mimicStyle: MimicStyle?
    var mimicAttemptStyles: [UUID: MimicStyle]?
    var archived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        mode: PracticeMode,
        prompt: String,
        keepsRecordings: Bool,
        takes: [PracticeSession] = [],
        mimicReference: MimicReference? = nil,
        mimicStyle: MimicStyle? = nil,
        mimicAttemptStyles: [UUID: MimicStyle]? = nil,
        archived: Bool = false
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
    }

    var latestTake: PracticeSession? { takes.last }
    var takeCount: Int { takes.count }
    var totalDuration: Double { takes.reduce(0) { $0 + $1.result.metrics.duration } }

    var isMimic: Bool { mode == .mimic }
    var trimmedPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Visible grouping for repeating general work. Mimic is a separate workspace.
    var isRetryStack: Bool { !isMimic && (!trimmedPrompt.isEmpty || takes.count >= 2) }
    var isStandaloneRecording: Bool { !isMimic && trimmedPrompt.isEmpty && takes.count == 1 }
    var isEmptyLegacy: Bool { !isMimic && takes.isEmpty }

    func takeNumber(for takeID: UUID) -> Int? {
        guard let index = takes.firstIndex(where: { $0.id == takeID }) else { return nil }
        return index + 1
    }

    func userRecordedDuration() -> Double {
        takes.reduce(0) { sum, take in
            take.takeSource == .recorded ? sum + take.result.metrics.duration : sum
        }
    }

    fileprivate var allPracticeTakes: [PracticeSession] {
        var items = takes
        if let reference = mimicReference?.take {
            items.append(reference)
        }
        return items
    }

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, updatedAt, mode, prompt, keepsRecordings, takes
        case mimicReference, mimicStyle, mimicAttemptStyles, archived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        mode = try container.decode(PracticeMode.self, forKey: .mode)
        prompt = try container.decode(String.self, forKey: .prompt)
        keepsRecordings = try container.decode(Bool.self, forKey: .keepsRecordings)
        takes = try container.decodeIfPresent([PracticeSession].self, forKey: .takes) ?? []
        mimicReference = try container.decodeIfPresent(MimicReference.self, forKey: .mimicReference)
        mimicStyle = try container.decodeIfPresent(MimicStyle.self, forKey: .mimicStyle)
        mimicAttemptStyles = try container.decodeIfPresent([UUID: MimicStyle].self, forKey: .mimicAttemptStyles)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(mode, forKey: .mode)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(keepsRecordings, forKey: .keepsRecordings)
        try container.encode(takes, forKey: .takes)
        try container.encodeIfPresent(mimicReference, forKey: .mimicReference)
        try container.encodeIfPresent(mimicStyle, forKey: .mimicStyle)
        try container.encodeIfPresent(mimicAttemptStyles, forKey: .mimicAttemptStyles)
        if archived { try container.encode(true, forKey: .archived) }
    }
}

enum RecordingTitle {
    static func make(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM, h:mm a"
        return "Recording · \(formatter.string(from: date))"
    }
}

/// User-facing library row. Mimic references are never included.
struct LibraryRecording: Identifiable, Equatable {
    let sessionID: UUID
    let take: PracticeSession
    let groupName: String
    let prompt: String
    let isMimicAttempt: Bool
    let mimicSourceName: String?
    let takeNumber: Int
    let takeCount: Int
    let isRetryStack: Bool
    let archived: Bool

    var id: UUID { take.id }
    var isImported: Bool { take.takeSource != .recorded }

    var displayTitle: String {
        if isMimicAttempt {
            let source = mimicSourceName.flatMap { $0.isEmpty ? nil : $0 } ?? groupName
            return "\(source) · Take \(takeNumber) · \(Self.timeText(take.createdAt))"
        }
        if isRetryStack {
            return "\(stackLabel) · Take \(takeNumber) · \(Self.timeText(take.createdAt))"
        }
        return groupName
    }

    var subtitle: String {
        if isMimicAttempt { return "Mimic attempt" }
        if isRetryStack { return prompt.isEmpty ? "Take \(takeNumber) of \(takeCount)" : prompt }
        return take.takeSource.title
    }

    var accessibilityLabel: String {
        if isMimicAttempt {
            let source = mimicSourceName ?? groupName
            return "Take \(takeNumber) of \(takeCount), Mimic, \(source)"
        }
        if isRetryStack {
            return "Take \(takeNumber) of \(takeCount), \(stackLabel)"
        }
        return "\(groupName), \(take.takeSource.title)"
    }

    var stackLabel: String {
        guard !prompt.isEmpty else { return groupName }
        let excerpt = prompt.split(separator: " ").prefix(8).joined(separator: " ")
        guard prompt.count > excerpt.count else { return excerpt }
        return "\(excerpt)…"
    }

    private static func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func make(session: CoachingSession, take: PracticeSession) -> LibraryRecording? {
        guard let number = session.takeNumber(for: take.id) else { return nil }
        return LibraryRecording(
            sessionID: session.id,
            take: take,
            groupName: session.name,
            prompt: session.trimmedPrompt,
            isMimicAttempt: session.isMimic,
            mimicSourceName: session.mimicReference?.sourceName,
            takeNumber: number,
            takeCount: session.takeCount,
            isRetryStack: session.isRetryStack,
            archived: session.archived
        )
    }

    func matches(query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if displayTitle.localizedCaseInsensitiveContains(query) { return true }
        if groupName.localizedCaseInsensitiveContains(query) { return true }
        if prompt.localizedCaseInsensitiveContains(query) { return true }
        if mimicSourceName?.localizedCaseInsensitiveContains(query) == true { return true }
        if take.takeSource.title.localizedCaseInsensitiveContains(query) { return true }
        return take.transcription?.text.localizedCaseInsensitiveContains(query) == true
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case recorded
    case imported
    case mimic

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .recorded: "Recorded"
        case .imported: "Imported"
        case .mimic: "Mimic"
        }
    }

    func matches(_ recording: LibraryRecording) -> Bool {
        switch self {
        case .all: true
        case .recorded: !recording.isImported && !recording.isMimicAttempt
        case .imported: recording.isImported && !recording.isMimicAttempt
        case .mimic: recording.isMimicAttempt
        }
    }
}

enum RecordingCatalog {
    static func recordings(from sessions: [CoachingSession], includeArchived: Bool = false) -> [LibraryRecording] {
        sessions.flatMap { session in
            if session.isMimic, session.archived, !includeArchived { return [] as [LibraryRecording] }
            return session.takes.compactMap { LibraryRecording.make(session: session, take: $0) }
        }
        .sorted { $0.take.createdAt > $1.take.createdAt }
    }

    static func recording(takeID: UUID, in sessions: [CoachingSession]) -> LibraryRecording? {
        for session in sessions {
            if let take = session.takes.first(where: { $0.id == takeID }) {
                return LibraryRecording.make(session: session, take: take)
            }
        }
        return nil
    }
}

enum AppDestination: Equatable {
    case home
    case mimicStart
    case practice(UUID)
    case take(UUID, UUID)
    case library
    case mimics

    var navigationSection: NavigationSection {
        switch self {
        case .home, .mimicStart: .home
        case .practice: .mimics
        case .take: .library
        case .library: .library
        case .mimics: .mimics
        }
    }

    var isTake: Bool {
        if case .take = self { return true }
        return false
    }

    var isWorkspace: Bool {
        switch self {
        case .practice, .take: true
        default: false
        }
    }
}

enum NavigationSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case library = "Library"
    case mimics = "Mimics"

    var id: Self { self }

    var title: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "waveform"
        case .library: "rectangle.stack"
        case .mimics: "waveform.path"
        }
    }
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

final class SessionStore {
    static let currentSchemaVersion = 3
    static let analysisSchemaVersion = 1

    let rootURL: URL
    private let libraryURL: URL

    init(rootURL: URL? = nil) throws {
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

    func load() throws -> [CoachingSession] {
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
    func save(_ sessions: [CoachingSession], analysisTakeIDs: Set<UUID>? = nil) throws {
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

    func recordingURL(sessionID: UUID, takeID: UUID) throws -> URL {
        try takeDirectory(sessionID: sessionID)
            .appendingPathComponent("take-\(takeID.uuidString).wav")
    }

    func importedAudioURL(sessionID: UUID, takeID: UUID, fileExtension: String) throws -> URL {
        let normalizedExtension = fileExtension.isEmpty ? "wav" : fileExtension.lowercased()
        return try takeDirectory(sessionID: sessionID)
            .appendingPathComponent("take-\(takeID.uuidString)-imported.\(normalizedExtension)")
    }

    func referenceURL(sessionID: UUID) throws -> URL {
        try takeDirectory(sessionID: sessionID).appendingPathComponent("reference.wav")
    }

    func analysisURL(sessionID: UUID, takeID: UUID) -> URL {
        rootURL
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
            .appendingPathComponent("take-\(takeID.uuidString).analysis.json")
    }

    func takeDirectory(sessionID: UUID) throws -> URL {
        let directory = rootURL
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func deleteSessionData(sessionID: UUID) throws {
        let directory = rootURL
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    func deleteTakeAnalysis(sessionID: UUID, takeID: UUID) throws {
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

    private func migrateFatLibrary(_ sessions: [CoachingSession], priorData: Data, priorVersion: Int) throws {
        let backupName = priorVersion == 1
            ? "session-library-v1-backup.json"
            : "session-library-v2-backup.json"
        let backup = rootURL.appendingPathComponent(backupName)
        if !FileManager.default.fileExists(atPath: backup.path) {
            try priorData.write(to: backup, options: .atomic)
        }
        try save(sessions, analysisTakeIDs: nil)
    }

    private func analysisTargets(in session: CoachingSession, analysisTakeIDs: Set<UUID>?) -> [PracticeSession] {
        guard let analysisTakeIDs else { return session.allPracticeTakes }
        return session.allPracticeTakes.filter { take in
            analysisTakeIDs.contains(take.id)
                || !FileManager.default.fileExists(atPath: analysisURL(sessionID: session.id, takeID: take.id).path)
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
            audioURL: try takeDirectory(sessionID: sessionID).appendingPathComponent(stored.audioFileName),
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
                  !keeping.contains(takeID) else { continue }
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
