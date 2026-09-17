import Foundation
import VoiceCoachCore

enum PracticeMode: String, Codable, CaseIterable, Identifiable {
    case general
    case prompt
    case freeSpeaking
    case mimic

    // Keep legacy cases decodable for existing libraries, but offer only these
    // two distinct workflows when creating a new session.
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
        mimicAttemptStyles: [UUID: MimicStyle]? = nil
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
    }

    var latestTake: PracticeSession? { takes.last }
    var takeCount: Int { takes.count }
    var totalDuration: Double { takes.reduce(0) { $0 + $1.result.metrics.duration } }
}

enum AppDestination: Equatable {
    case studio
    case create
    case practice(UUID)
    case take(UUID, UUID)
    case sessions
    case insights

    var navigationSection: NavigationSection {
        switch self {
        case .studio, .create, .practice, .take: .studio
        case .sessions: .sessions
        case .insights: .insights
        }
    }

    var isTake: Bool {
        if case .take = self { return true }
        return false
    }
}

enum NavigationSection: String, CaseIterable, Identifiable {
    case studio = "Studio"
    case sessions = "Sessions"
    case insights = "Insights"

    var id: Self { self }

    var title: String {
        self == .sessions ? "All Sessions" : rawValue
    }

    var symbol: String {
        switch self {
        case .studio: "waveform"
        case .sessions: "rectangle.stack"
        case .insights: "chart.xyaxis.line"
        }
    }
}

private struct SessionLibraryDocument: Codable {
    let schemaVersion: Int
    let sessions: [CoachingSession]
}

final class SessionStore {
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
        let document = try JSONDecoder().decode(SessionLibraryDocument.self, from: data)
        guard document.schemaVersion == 1 || document.schemaVersion == 2 else {
            throw CocoaError(.coderReadCorrupt)
        }
        return document.sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ sessions: [CoachingSession]) throws {
        if FileManager.default.fileExists(atPath: libraryURL.path),
           let existing = try? Data(contentsOf: libraryURL),
           let prior = try? JSONDecoder().decode(SessionLibraryDocument.self, from: existing),
           prior.schemaVersion == 1 {
            let backup = rootURL.appendingPathComponent("session-library-v1-backup.json")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try existing.write(to: backup, options: .atomic)
            }
        }
        let document = SessionLibraryDocument(schemaVersion: 2, sessions: sessions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: libraryURL, options: .atomic)
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

    private func takeDirectory(sessionID: UUID) throws -> URL {
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
}
