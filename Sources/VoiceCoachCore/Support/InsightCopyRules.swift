import Foundation

/// Deterministic validator for Insight wording (gates 4–7).
/// Rejects return `nil`; the resolver then fail-closes to frozen `CoachObservation`.
public enum InsightCopyRules: Sendable {
  public static let maxObservationCharacters = 140
  public static let maxActionCharacters = 120
  public static let maxObservationWords = 24
  public static let maxActionWords = 20
  public static let minObservationWords = 6
  public static let minActionWords = 5

  private static let wrappingCharacters = CharacterSet(charactersIn: "\"'“”‘’")

  /// Clinical / psych / emotion / confidence / diagnosis / treatment stems (gate 5).
  private static let deniedSubstrings = [
    "diagnos", "medical", "medicine", "clinical", "clinician",
    "diaphragm", "therapy", "therapist", "disorder", "dysphonia",
    "patholog", "disease", "symptom", "treatment", "prescription",
    "damaged voice", "vocal cord", "vocal fold", "nodule", "polyp",
    "anxiety", "anxious", "nervous", "confidence", "confident",
    "boredom", "boring", "emotion", "depression", "trauma",
    "worr", "hesitat", "insecur", "timid", "scared", "fear",
    "please", "baseline", "throat",
    "filler", "words per minute", "wpm",
    "breath support", "room projection",
    "thinking pause", "overthinking",
  ]

  private static let pauseForbidden = [
    "pitch", "intonation", "melody", "monotone", "semitone",
    "loudness", "volume", "filler", "wpm",
  ]

  private static let pitchForbidden = [
    "pause", "gap", "silence", "loudness", "volume", "filler", "wpm",
  ]

  private static let numberWords: Set<String> = [
    "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
    "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
    "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty",
    "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "percent",
  ]

  private static let unitTokens: Set<String> = [
    "ms", "hz", "db", "dbfs", "st", "semitone", "semitones", "wpm",
  ]

  public static func acceptedObservation(
    rewrite: InsightCopyRewrite,
    packet: HeroPacket
  ) -> CoachObservation? {
    guard packet.isValid else { return nil }
    guard let observation = sanitize(rewrite.observation, maxCharacters: maxObservationCharacters, minWords: minObservationWords, maxWords: maxObservationWords)
    else { return nil }
    guard let action = sanitize(rewrite.action, maxCharacters: maxActionCharacters, minWords: minActionWords, maxWords: maxActionWords)
    else { return nil }
    guard observation != action else { return nil }

    let combined = observation + " " + action
    guard passesDenyList(combined) else { return nil }
    guard containsNoInventedNumbers(combined, canonical: packet.canonicalObservation + " " + packet.canonicalAction)
    else { return nil }
    guard staysOnAxis(observation: observation, action: action, axis: packet.axis) else {
      return nil
    }

    return CoachObservation(summary: observation, action: action)
  }

  public static func sanitize(
    _ raw: String,
    maxCharacters: Int,
    minWords: Int,
    maxWords: Int
  ) -> String? {
    let text =
      raw
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: wrappingCharacters)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let collapsed = collapseWhitespace(text)
    guard !collapsed.isEmpty else { return nil }
    guard collapsed.count <= maxCharacters else { return nil }
    guard !containsMarkup(collapsed) else { return nil }

    let words = wordCount(collapsed)
    guard words >= minWords, words <= maxWords else { return nil }
    return collapsed
  }

  private static func collapseWhitespace(_ text: String) -> String {
    text.split { $0.isWhitespace || $0.isNewline }.joined(separator: " ")
  }

  private static func containsMarkup(_ text: String) -> Bool {
    let lower = text.lowercased()
    if lower.contains("http://") || lower.contains("https://") || lower.contains("www.") {
      return true
    }
    if text.contains("](") || text.contains("**") || text.contains("`") || text.contains("#") {
      return true
    }
    return false
  }

  private static func passesDenyList(_ text: String) -> Bool {
    let lower = text.lowercased()
    for token in deniedSubstrings where lower.contains(token) {
      return false
    }
    return true
  }

  private static func containsNoInventedNumbers(_ rewrite: String, canonical: String) -> Bool {
    let rewriteDigits = digitRuns(in: rewrite)
    let canonicalDigits = Set(digitRuns(in: canonical))
    if rewriteDigits.contains(where: { !canonicalDigits.contains($0) }) {
      return false
    }

    let rewriteTokens = tokenSet(rewrite)
    let canonicalTokens = tokenSet(canonical)
    let invented = rewriteTokens.subtracting(canonicalTokens)
    if invented.contains(where: { numberWords.contains($0) || unitTokens.contains($0) }) {
      return false
    }
    return true
  }

  private static func staysOnAxis(observation: String, action: String, axis: CoachingHeroAxis)
    -> Bool
  {
    let obs = observation.lowercased()
    let act = action.lowercased()
    let combined = obs + " " + act
    switch axis {
    case .pause:
      guard obs.contains("pause") || obs.contains("gap") else { return false }
      guard act.contains("pause") || act.contains("gap") || act.contains("phrase") else {
        return false
      }
      return pauseForbidden.allSatisfy { !combined.contains($0) }
    case .pitch:
      guard obs.contains("pitch"), act.contains("pitch") else { return false }
      return pitchForbidden.allSatisfy { !combined.contains($0) }
    }
  }

  private static func digitRuns(in text: String) -> [String] {
    var runs: [String] = []
    var current = ""
    for character in text {
      if character.isNumber {
        current.append(character)
      } else if !current.isEmpty {
        runs.append(current)
        current = ""
      }
    }
    if !current.isEmpty { runs.append(current) }
    return runs
  }

  private static func tokenSet(_ text: String) -> Set<String> {
    Set(
      text.lowercased().split { $0.isWhitespace || $0.isNewline || $0.isPunctuation }.map(String.init)
    )
  }

  private static func wordCount(_ text: String) -> Int {
    text.split { $0.isWhitespace || $0.isNewline }.count
  }
}
