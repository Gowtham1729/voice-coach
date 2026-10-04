import Foundation
import Testing

@testable import VoiceCoachCore

#if canImport(Speech)
  import CoreMedia
  import Speech
#endif

@Suite("Transcription languages")
struct TranscriptionLanguageTests {
  @Test("Apple's saved language never steers automatic Parakeet transcription")
  func engineLanguagePreference() {
    #expect(
      TranscriptionLanguagePreference.requestedLocale(
        for: "ja_JP", engine: .parakeet) == nil)
    #expect(
      TranscriptionLanguagePreference.requestedLocale(
        for: "ja_JP", engine: .system)?.identifier == "ja_JP")
    #expect(
      TranscriptionLanguagePreference.requestedLocale(
        for: "", engine: .system) == Locale.current)
  }

  @Test("Unsupported speech never selects an unrelated language")
  func unsupportedLocale() {
    let supported = [Locale(identifier: "en_US"), Locale(identifier: "fr_FR")]
    #expect(
      TranscriptionLanguagePreference.matchingLocale(
        for: Locale(identifier: "ja_JP"), supported: supported) == nil)
    #expect(
      TranscriptionLanguagePreference.matchingLocale(
        for: Locale(identifier: "ja_JP"), supported: []) == nil)
  }

  @Test("Locale resolution respects language and prefers a matching region")
  func equivalentLocale() {
    let supported = ["fr_CA", "en_US", "fr_FR"].map(Locale.init(identifier:))
    #expect(
      TranscriptionLanguagePreference.matchingLocale(
        for: Locale(identifier: "fr-FR"), supported: supported)?.identifier == "fr_FR")
    #expect(
      TranscriptionLanguagePreference.matchingLocale(
        for: Locale(identifier: "fr_BE"), supported: supported)?.language.languageCode?.identifier
        == "fr")
  }

  @Test("Legacy transcripts decode without language or engine metadata")
  func legacyTranscript() throws {
    let result = try JSONDecoder().decode(
      TranscriptionResult.self, from: Data(#"{"text":"Bonjour","words":[]}"#.utf8))
    #expect(result.localeIdentifier == nil)
    #expect(result.engine == nil)
    let identified = TranscriptionResult(
      text: "こんにちは", words: [], localeIdentifier: "ja_JP", engine: .system)
    #expect(
      try JSONDecoder().decode(
        TranscriptionResult.self, from: JSONEncoder().encode(identified)) == identified)
  }

  @Test("Japanese is rejected before launching the European Parakeet model")
  func incompatibleParakeet() async {
    do {
      _ = try await TranscriptionService(
        preferredEngine: .parakeet, locale: Locale(identifier: "ja_JP")
      ).transcribe(url: URL(fileURLWithPath: "/unused.wav"))
      Issue.record("Japanese must not reach Parakeet v3")
    } catch TranscriptionError.modelLanguageUnsupported(let language) {
      #expect(language == "ja_JP")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
    #expect(NemoSpeechTranscriber.supports(locale: Locale(identifier: "fr_FR")))
  }

  @Test("Japanese character spans form language tokens while phrase spans remain intact")
  func japaneseSegmentation() {
    let text = "今回の練習。"
    let words = text.enumerated().map { index, character in
      TranscriptWord(word: String(character), start: Double(index), end: Double(index + 1))
    }
    let grouped = AppleTranscriptSegmenter.group(
      words: words, ranges: words.indices.map { $0..<($0 + 1) },
      text: text, locale: Locale(identifier: "ja_JP"))
    #if canImport(NaturalLanguage)
      #expect(grouped.map(\.word) == ["今回", "の", "練習"])
      #expect(grouped[0].start == 0 && grouped[0].end == 2)
    #endif
    let phrase = [TranscriptWord(word: text, start: 1, end: 3)]
    #expect(
      AppleTranscriptSegmenter.group(
        words: phrase, ranges: [0..<text.count], text: text,
        locale: Locale(identifier: "ja_JP")) == phrase)
  }

  #if canImport(Speech)
    @Test("Apple phrase timings are preserved and confidence fragments stay together")
    func nativeTimedSpans() {
      let range = CMTimeRange(
        start: CMTime(seconds: 1, preferredTimescale: 100),
        duration: CMTime(seconds: 2, preferredTimescale: 100))
      var first = AttributedString("Bonjour ")
      first.audioTimeRange = range
      first.transcriptionConfidence = 0.9
      var second = AttributedString("tout le monde.")
      second.audioTimeRange = range
      second.transcriptionConfidence = 0.7
      let words = AppleSpeechTranscriber.timedWords(in: first + second, fallbackRange: range)
      #expect(
        words == [TranscriptWord(word: "Bonjour tout le monde.", start: 1, end: 3, confidence: 0.7)]
      )
      let japanese = AppleSpeechTranscriber.timedWords(
        in: AttributedString("こんにちは。"), fallbackRange: range)
      #expect(japanese == [TranscriptWord(word: "こんにちは。", start: 1, end: 3)])
    }
  #endif
}
