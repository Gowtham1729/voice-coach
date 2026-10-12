import Foundation

/// Locked copy for the one-target retry card (James, 2026-10-12).
/// Follows strict copy locks:
/// - Curly single quotes ‘ ’ around words and phrases
/// - Phrases > 5 words truncated to first 4 words + … inside quotes
/// - No numbers anywhere in the card
/// - No em dashes
/// - Never "worse" or "improved"
public enum OneTargetRetryStrings {
  // MARK: - Chips
  public static let yourTake = "Your take"
  public static let referenceChip = "Reference"

  // MARK: - Buttons & Links
  public static let tryAgain = "Try again"
  public static let skip = "Skip"
  public static let thatWasOnPurpose = "That was on purpose"
  public static let noTranscript = "No transcript for this take."
  public static let addReference = "Add reference…"
  public static let replayBoth = "Replay both"

  // MARK: - No Cue Neutral Lines
  public static let noLongPauses = "No long pauses in this take."
  public static let noReferenceAlignment = "This take didn’t line up with the reference enough for a cue."

  // MARK: - Phrase & Word Quoting Helper

  /// Wraps a word or phrase in curly single quotes ‘ ’.
  /// If the text has more than 5 words, truncates to the first 4 words followed by ‘…’.
  public static func formatWordOrPhrase(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    if words.count > 5 {
      let firstFour = words.prefix(4).joined(separator: " ")
      return "‘\(firstFour)…’"
    } else {
      return "‘\(trimmed)’"
    }
  }

  // MARK: - Reference Cues

  /// Pitch / emphasis cue on a word.
  public static func pitchCue(word: String) -> String {
    "Make \(formatWordOrPhrase(word)) stand out, like the reference."
  }

  /// Loudness / energy cue on a phrase.
  public static func loudnessCue(phrase: String) -> String {
    "Match the reference’s energy on \(formatWordOrPhrase(phrase))."
  }

  /// Timing / pace cue on a phrase.
  public static func timingCue(phrase: String) -> String {
    "Take \(formatWordOrPhrase(phrase)) at the reference’s pace."
  }

  // MARK: - Plain Take Cue

  /// Plain-take longest pause cue.
  public static func plainPauseCue(word: String) -> String {
    "You paused before \(formatWordOrPhrase(word))."
  }

  // MARK: - Retry Verdicts (Reference Takes)

  /// Word or phrase closer to the reference.
  public static func closerVerdict(target: String) -> String {
    "\(formatWordOrPhrase(target)) was closer to the reference this time."
  }

  /// Change was within take-to-take noise floor.
  public static let withinNoiseVerdict = "About the same as your last take."

  /// Target word could not be aligned in this retry take.
  public static func wordNotFound(word: String) -> String {
    "Couldn’t find \(formatWordOrPhrase(word)) in this take."
  }

  /// Gap fell below the target threshold ("close enough").
  public static func closeEnoughVerdict(target: String) -> String {
    "\(formatWordOrPhrase(target)) is close to the reference now."
  }
}
