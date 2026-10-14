import Foundation

/// Locked copy for the one-target retry card (James, PR #119 string rewrite).
/// Follows strict copy locks:
/// - Curly single quotes ‘ ’ around words and phrases
/// - Phrases > 5 words truncated to first 4 words + … inside quotes
/// - No measured values in the card (transcript words may contain numerals)
/// - No em dashes
/// - No negative or promotional progress labels
public enum OneTargetRetryStrings {
  // MARK: - Chips
  public static let yourTake = "Your take"
  public static let previousTake = "Previous take"
  public static let thisTake = "This take"
  public static let referenceChip = "Clip"

  // MARK: - Buttons & Links
  public static let tryAgain = "Try again"
  public static let skip = "Skip"
  public static let skipped = "Skipped for this take."
  public static let skippedSeparator = "·"
  public static let show = "Show"
  public static let thatWasOnPurpose = "That was on purpose"
  public static let noTranscript = "No transcript for this take."
  public static let addReference = "Add a clip…"
  public static let replayBoth = "Replay both"

  // MARK: - No Cue Neutral Lines
  public static let noLongPauses = "No long pauses in this take."
  public static let noReferenceAlignment = "Not enough of your words matched the clip to suggest a fix. Replay both to compare."
  public static let noNonEnglishWordCue = "Tips for single words work in English for now. Replay both to compare by ear."
  public static let NEUTRAL_RETRY_LINE = "The difference is too small for us to tell. Listen to ‘{word}’ in each take."

  public static func neutralRetryLine(word: String) -> String {
    NEUTRAL_RETRY_LINE.replacingOccurrences(of: "‘{word}’", with: formatWordOrPhrase(word))
  }

  // MARK: - Phrase & Word Quoting Helper

  /// Wraps a word or phrase in curly single quotes ‘ ’.
  /// If the text has more than 5 words, truncates to the first 4 words followed by ‘…’.
  public static func formatWordOrPhrase(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    if words.count > 5 {
      let firstFour = words.prefix(4).joined(separator: " ")
      return "‘\(firstFour) …’"
    } else {
      return "‘\(trimmed)’"
    }
  }

  // MARK: - Reference Cues

  /// Pitch / emphasis cue on a word.
  public static func pitchCue(word: String) -> String {
    "Make \(formatWordOrPhrase(word)) stand out, like the clip does."
  }

  /// Loudness / energy cue on a phrase.
  public static func loudnessCue(phrase: String) -> String {
    "Say \(formatWordOrPhrase(phrase)) as strongly as the clip does."
  }

  /// Timing / pace cue on a phrase.
  public static func timingCue(phrase: String) -> String {
    "Say \(formatWordOrPhrase(phrase)) at the clip’s speed."
  }

  // MARK: - Plain Take Cue

  /// Plain-take longest pause cue.
  public static func plainPauseCue(word: String) -> String {
    "Your longest pause was before \(formatWordOrPhrase(word))."
  }

  public static func playPauseBefore(word: String) -> String {
    "Play the pause before \(formatWordOrPhrase(word))"
  }

  public static func playWordInYourTake(_ word: String) -> String {
    "Play \(formatWordOrPhrase(word)) in your take"
  }

  public static func playWordInClip(_ word: String) -> String {
    "Play \(formatWordOrPhrase(word)) in the clip"
  }

  // MARK: - Retry Verdicts (Reference Takes)

  /// Word or phrase closer to the reference.
  public static func closerVerdict(target: String) -> String {
    "\(formatWordOrPhrase(target)) was closer to the clip this time."
  }

  /// Change was within take-to-take noise floor.
  public static let withinNoiseVerdict = "About the same as your last take."

  /// Target word could not be aligned in this retry take.
  public static func wordNotFound(word: String) -> String {
    "Couldn’t find \(formatWordOrPhrase(word)) in this take. Say the whole phrase again."
  }

  /// Gap fell below the target threshold ("close enough").
  public static func closeEnoughVerdict(target: String) -> String {
    "\(formatWordOrPhrase(target)) is close to the clip now."
  }
}
