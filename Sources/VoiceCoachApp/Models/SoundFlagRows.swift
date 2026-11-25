import Foundation
import VoiceCoachCore

/// One flag in Review's Sounds section (UX-2): a Reference word that sounded different.
struct SoundFlagRow: Identifiable, Equatable {
  /// Index into the Reference transcript's words.
  let referenceWordIndex: Int
  let word: String
  /// What the transcript heard instead, when FR-1 found the same word.
  let heard: String?
  /// Reference clock.
  let referenceRange: ClosedRange<Double>
  /// Take clock. Nil when the word could not be placed in the take (no Listen then).
  let takeRange: ClosedRange<Double>?
  /// Index into the take transcript's words, for the quiet mark in Compare (UX-1).
  let takeWordIndex: Int?

  var id: Int { referenceWordIndex }
}

/// One part of the Listen sequence (FR-17).
struct SoundListenSegment: Equatable {
  let source: MimicPlaybackSource
  let range: ClosedRange<Double>
}

enum SoundFlagRows {
  /// Flags, strongest first, placed on both clocks. At most the engine's limit (FR-8).
  static func make(
    result: SoundComparisonResult, reference: PracticeSession, attempt: PracticeSession,
    comparison: MimicComparison
  ) -> [SoundFlagRow] {
    let referenceWords = reference.transcription?.words ?? []
    let attemptWords = attempt.transcription?.words ?? []
    return result.flags.compactMap { flag in
      guard referenceWords.indices.contains(flag.wordIndex) else { return nil }
      let referenceWord = referenceWords[flag.wordIndex]
      let heardDifferently = comparison.heardDifferently.first {
        $0.referenceIndex == flag.wordIndex
      }
      let pairedIndex =
        comparison.pairs.first { $0.referenceIndex == flag.wordIndex }?.attemptIndex
        ?? heardDifferently?.attemptIndex
      let span = result.takeSpan(wordIndex: flag.wordIndex)
      let takeWordIndex = pairedIndex ?? span.flatMap { mostOverlapping($0, in: attemptWords) }
      var takeRange = span
      if takeRange == nil, let index = takeWordIndex, attemptWords.indices.contains(index) {
        takeRange = attemptWords[index].start...attemptWords[index].end
      }
      return SoundFlagRow(
        referenceWordIndex: flag.wordIndex,
        word: displayWord(referenceWord.word),
        heard: heardDifferently.map { displayWord($0.attempt.word) },
        referenceRange: referenceWord.start...max(referenceWord.start, referenceWord.end),
        takeRange: takeRange,
        takeWordIndex: takeWordIndex)
    }
  }

  /// A word the transcript heard differently (FR-1), as a row with its own Listen.
  static func heardRow(_ difference: MimicHeardDifference) -> SoundFlagRow {
    let reference = difference.reference
    let attempt = difference.attempt
    return SoundFlagRow(
      referenceWordIndex: difference.referenceIndex,
      word: displayWord(reference.word),
      heard: displayWord(attempt.word),
      referenceRange: reference.start...max(reference.start, reference.end),
      takeRange: attempt.end > attempt.start ? attempt.start...attempt.end : nil,
      takeWordIndex: difference.attemptIndex)
  }

  /// Reference word, your word, Reference word, each with a little room around it (FR-17).
  static func listenSequence(
    for row: SoundFlagRow, referenceDuration: Double, takeDuration: Double
  ) -> [SoundListenSegment] {
    guard let takeRange = row.takeRange else { return [] }
    let reference = padded(row.referenceRange, duration: referenceDuration)
    let take = padded(takeRange, duration: takeDuration)
    guard let reference, let take else { return [] }
    return [
      .init(source: .reference, range: reference),
      .init(source: .attempt, range: take),
      .init(source: .reference, range: reference),
    ]
  }

  /// Silence between the parts of the Listen sequence.
  static let listenGap: Duration = .milliseconds(400)

  static func displayWord(_ word: String) -> String {
    word.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
  }

  private static func padded(_ range: ClosedRange<Double>, duration: Double)
    -> ClosedRange<Double>?
  {
    let start = max(0, range.lowerBound - 0.08)
    let end = min(duration, range.upperBound + 0.08)
    return end > start ? start...end : nil
  }

  private static func mostOverlapping(_ span: ClosedRange<Double>, in words: [TranscriptWord])
    -> Int?
  {
    var best: (index: Int, overlap: Double)?
    for (index, word) in words.enumerated() {
      let overlap = min(span.upperBound, word.end) - max(span.lowerBound, word.start)
      if overlap > 0, overlap > (best?.overlap ?? 0) { best = (index, overlap) }
    }
    return best?.index
  }
}
