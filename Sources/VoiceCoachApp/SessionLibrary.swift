import Foundation
import VoiceCoachCore

enum PracticeMode: String, Codable, CaseIterable, Identifiable {
    case general
    case prompt
    case freeSpeaking

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General practice"
        case .prompt: "Read a prompt"
        case .freeSpeaking: "Free speaking"
        }
    }

    var detail: String {
        switch self {
        case .general: "Speak freely on any topic. Build consistency and confidence."
        case .prompt: "Read a short prompt aloud. Focus on clarity and delivery."
        case .freeSpeaking: "Speak on a topic of your choice. Develop structure and fluency."
        }
    }

    var icon: String {
        switch self {
        case .general: "mic.fill"
        case .prompt: "doc.text.fill"
        case .freeSpeaking: "chart.bar.fill"
        }
    }
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

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        mode: PracticeMode,
        prompt: String,
        keepsRecordings: Bool,
        takes: [PracticeSession] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mode = mode
        self.prompt = prompt
        self.keepsRecordings = keepsRecordings
        self.takes = takes
    }

    var latestTake: PracticeSession? { takes.last }
    var takeCount: Int { takes.count }
    var totalDuration: Double { takes.reduce(0) { $0 + $1.result.metrics.duration } }
}

enum AppDestination: Equatable {
    case studio
    case create
    case practice(UUID)
    case review(UUID, UUID)
    case sessions
    case insights
    case settings

    var navigationSection: NavigationSection {
        switch self {
        case .studio, .create, .practice, .review: .studio
        case .sessions: .sessions
        case .insights: .insights
        case .settings: .settings
        }
    }
}

enum NavigationSection: String, CaseIterable, Identifiable {
    case studio = "Studio"
    case sessions = "Sessions"
    case insights = "Insights"
    case settings = "Settings"

    var id: Self { self }
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
        guard document.schemaVersion == 1 else {
            throw CocoaError(.coderReadCorrupt)
        }
        return document.sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ sessions: [CoachingSession]) throws {
        let document = SessionLibraryDocument(schemaVersion: 1, sessions: sessions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: libraryURL, options: .atomic)
    }

    func recordingURL(sessionID: UUID, takeID: UUID) throws -> URL {
        let directory = rootURL
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("take-\(takeID.uuidString).wav")
    }

    func deleteSessionData(sessionID: UUID) throws {
        let directory = rootURL
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
