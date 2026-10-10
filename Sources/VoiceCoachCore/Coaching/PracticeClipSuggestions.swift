import Foundation

/// A short, timestamped phrase from a recording. Suggestions are derived locally
/// and are not persisted; the resulting reference uses the existing session format.
public struct SuggestedPracticeClip: Identifiable, Equatable, Sendable {
  public let id: Int
  public let start: Double
  public let end: Double
  public let transcription: TranscriptionResult

  public var duration: Double { end - start }
  public var text: String { transcription.text }
}

public enum PracticeClipSuggestions {
  /// Prefer sentence endings and pauses, keeping long passages to repeatable spans.
  /// Without usable word timing, leave the manual trim flow available rather than
  /// guessing which audio belongs to a transcript.
  public static func clips(
    transcription: TranscriptionResult?, duration: Double
  ) -> [SuggestedPracticeClip] {
    guard let transcription, duration.isFinite, duration >= 1,
      !transcription.words.isEmpty
    else { return [] }
    let words = transcription.words
    for (index, word) in words.enumerated() {
      guard word.start.isFinite, word.end.isFinite,
        word.start >= 0, word.end > word.start, word.end <= duration,
        word.end - word.start <= 14.7,
        !word.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        index == 0 || word.start >= words[index - 1].end
      else { return [] }
    }

    var groups: [Range<Int>] = []
    var first = 0
    for index in words.indices {
      let span = words[index].end - words[first].start
      let next = index + 1
      let isLast = next == words.count
      let pause = isLast ? 0 : words[next].start - words[index].end
      let sentenceEnd = words[index].word.unicodeScalars.contains {
        ".!?。！？".unicodeScalars.contains($0)
      }
      let nextTooLong = !isLast && words[next].end - words[first].start > 14.7
      if isLast || nextTooLong || span >= 8 || pause >= 0.65 || (span >= 1 && sentenceEnd) {
        groups.append(first..<next)
        first = next
      }
    }

    return groups.compactMap { group in
      let firstWord = words[group.lowerBound]
      let lastWord = words[group.upperBound - 1]
      // Padding never includes a neighbouring word, even across a forced split.
      let leftLimit = group.lowerBound == 0 ? 0 : words[group.lowerBound - 1].end
      let rightLimit = group.upperBound == words.count ? duration : words[group.upperBound].start
      var start = max(leftLimit, firstWord.start - 0.12)
      var end = min(rightLimit, lastWord.end + 0.18)
      if end - start < 1 {
        end = min(rightLimit, start + 1)
        start = max(leftLimit, end - 1)
      }
      guard end - start >= 1, end - start <= 15 else { return nil }
      let excerptWords = words[group].map {
        TranscriptWord(
          word: $0.word, start: $0.start - start, end: $0.end - start,
          confidence: $0.confidence)
      }
      return SuggestedPracticeClip(
        id: group.lowerBound, start: start, end: end,
        transcription: TranscriptionResult(
          text: excerptWords.map(\.word).joined(separator: " "), words: excerptWords,
          localeIdentifier: transcription.localeIdentifier, engine: transcription.engine))
    }
  }
}
