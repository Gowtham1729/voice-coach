import Foundation

/// Preference for deferred on-device titles from transcripts.
/// Default is off when the key is unset (do not use raw `bool(forKey:)`).
enum AutoTitlePreference {
    static let storageKey = "voiceCoach.autoGenerateTitles"
    static let `default` = false

    static func load(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: storageKey) != nil else { return `default` }
        return defaults.bool(forKey: storageKey)
    }

    static var isEnabled: Bool { load() }
}

/// Transcript / title sanitizing without importing FoundationModels (keeps analyze path light).
enum SmartTitleRules {
    static let minTranscriptCharacters = 24
    static let minTranscriptWords = 5
    static let maxTranscriptCharacters = 1_800
    static let maxTitleCharacters = 56
    static let maxTitleWords = 8

    private static let forbiddenSubstrings = [
        "baseline", "throat", "please", "diagnos", "medical", "diaphragm", "therapy", "disorder"
    ]

    private static let wrappingCharacters = CharacterSet(charactersIn: "\"'“”‘’.!?")

    static func transcriptPassesGates(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minTranscriptCharacters else { return false }
        return wordCount(trimmed) >= minTranscriptWords
    }

    static func clipTranscript(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxTranscriptCharacters else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxTranscriptCharacters)
        return String(trimmed[..<end])
    }

    static func sanitize(_ raw: String) -> String? {
        let title = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: wrappingCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        guard title.count <= maxTitleCharacters else { return nil }

        let words = wordCount(title)
        guard words >= 1, words <= maxTitleWords else { return nil }

        let lower = title.lowercased()
        for token in forbiddenSubstrings where lower.contains(token) {
            return nil
        }
        return title
    }

    private static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
