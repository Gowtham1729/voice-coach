import Foundation

package enum SmartTitleRules {
  package static let minTranscriptCharacters = 24
  package static let minTranscriptWords = 5
  package static let maxTranscriptCharacters = 1_800
  package static let maxTitleCharacters = 56
  package static let maxTitleWords = 8

  private static let forbiddenSubstrings = [
    "baseline", "throat", "please", "diagnos", "medical", "diaphragm", "therapy", "disorder",
  ]

  private static let wrappingCharacters = CharacterSet(charactersIn: "\"'“”‘’.!?")

  package static func transcriptPassesGates(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= minTranscriptCharacters else { return false }
    return wordCount(trimmed) >= minTranscriptWords
  }

  package static func clipTranscript(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > maxTranscriptCharacters else { return trimmed }
    let end = trimmed.index(trimmed.startIndex, offsetBy: maxTranscriptCharacters)
    return String(trimmed[..<end])
  }

  package static func sanitize(_ raw: String) -> String? {
    let title =
      raw
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
