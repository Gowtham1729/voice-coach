import Foundation

#if canImport(NaturalLanguage)
  import NaturalLanguage
#endif

/// Groups native character spans for unspaced scripts without inventing timestamps inside a span.
enum AppleTranscriptSegmenter {
  static func group(
    words: [TranscriptWord], ranges: [Range<Int>], text: String, locale: Locale
  ) -> [TranscriptWord] {
    #if canImport(NaturalLanguage)
      guard let language = locale.language.languageCode?.identifier,
        ["ja", "zh", "yue"].contains(language), words.count == ranges.count
      else { return words }
      let tokenizer = NLTokenizer(unit: .word)
      tokenizer.string = text
      tokenizer.setLanguage(NLLanguage(rawValue: language))
      var tokenRanges: [Range<Int>] = []
      tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let end = text.distance(from: text.startIndex, to: range.upperBound)
        tokenRanges.append(start..<end)
        return true
      }

      var grouped: [TranscriptWord] = []
      var index = 0
      while index < words.count {
        guard
          words[index].word.unicodeScalars.contains(where: {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
          })
        else {
          index += 1
          continue
        }
        var last = index
        if let token = tokenRanges.first(where: { $0.overlaps(ranges[index]) }) {
          while last + 1 < words.count, ranges[last].upperBound < token.upperBound {
            last += 1
          }
        }
        let spans = words[index...last]
        let confidence =
          spans.allSatisfy { $0.confidence != nil }
          ? spans.compactMap(\.confidence).min() : nil
        grouped.append(
          TranscriptWord(
            word: spans.map(\.word).joined(), start: words[index].start,
            end: words[last].end, confidence: confidence))
        index = last + 1
      }
      return grouped
    #else
      return words
    #endif
  }
}
