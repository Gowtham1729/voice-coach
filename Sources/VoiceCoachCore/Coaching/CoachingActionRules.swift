import Foundation

/// The model may improve the phrasing of an exercise, never its measured observation.
/// An invalid or off-topic action leaves the deterministic exercise in place.
public enum CoachingActionRules {
  private static let denied = [
    "diagnos", "medical", "clinical", "therapy", "treatment", "disorder", "disease",
    "diaphragm", "throat", "vocal cord", "vocal fold", "anxiety", "confidence",
    "breath support", "perfect", "identical", "exactly", "always", "never",
  ]
  private static let numberWords: Set<String> = [
    "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    "twenty", "thirty", "forty", "fifty", "hundred",
  ]

  public static func accepted(_ raw: String, for signal: CoachingSignal) -> String? {
    let text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = text.lowercased()
    let folded = lower.unicodeScalars.filter {
      CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
    }.map(String.init).joined()
    let approvedTokens = tokens(in: signal.action)
    guard (20...150).contains(text.count),
      (5...26).contains(text.split(separator: " ").count),
      !text.contains(where: \.isNumber),
      !lower.contains("http"), !text.contains("#"), !text.contains("*"),
      denied.allSatisfy({ !lower.contains($0) }),
      quotedPhrases(in: text).allSatisfy({ signal.action.localizedCaseInsensitiveContains($0) }),
      namedWordTargets(in: text).allSatisfy({ approvedTokens.contains($0) }),
      numberWords.intersection(tokens(in: text)).isSubset(of: approvedTokens),
      signal.actionTerms.allSatisfy({ group in
        group.split(separator: "|").contains { term in
          lower.contains(term) || folded.contains(term)
        }
      })
    else { return nil }
    return text
  }

  private static func tokens(in text: String) -> Set<String> {
    Set(text.lowercased().split { !$0.isLetter }.map(String.init))
  }

  private static func quotedPhrases(in text: String) -> [String] {
    // Keep apostrophes inside words (for example, "reference's") out of quote spans.
    let pattern = #"“([^”]+)”|‘([^’]+)’|"([^"]+)"|(?<![\p{L}\p{N}])'([^']+)'"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return expression.matches(in: text, range: range).compactMap { match in
      (1...4).compactMap { group in
        Range(match.range(at: group), in: text).map { String(text[$0]) }
      }.first
    }
  }

  private static func namedWordTargets(in text: String) -> [String] {
    let pattern = #"\b(?:the|a)\s+word\s+([a-z][a-z'-]*)\b"#
    guard let expression = try? NSRegularExpression(
      pattern: pattern, options: [.caseInsensitive]) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return expression.matches(in: text, range: range).compactMap { match in
      Range(match.range(at: 1), in: text).map { String(text[$0]).lowercased() }
    }
  }
}
