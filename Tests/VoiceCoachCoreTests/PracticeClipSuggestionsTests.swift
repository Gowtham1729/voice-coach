import Foundation
import Testing
import VoiceCoachCore

@Suite("Suggested practice clips")
struct PracticeClipSuggestionsTests {
  @Test("Sentence boundaries produce padded excerpts with relative word times")
  func sentences() throws {
    let transcript = TranscriptionResult(
      text: "A short phrase. Another phrase!",
      words: [
        word("A", 0.4, 0.7), word("short", 0.8, 1.2), word("phrase.", 1.3, 1.8),
        word("Another", 2.1, 2.8), word("phrase!", 2.9, 3.6),
      ], localeIdentifier: "en_GB", engine: .system)
    let clips = PracticeClipSuggestions.clips(transcription: transcript, duration: 4)
    #expect(clips.count == 2)
    let first = try #require(clips.first)
    #expect(first.text == "A short phrase.")
    #expect(abs(first.start - 0.28) < 0.00001)
    #expect(abs(first.end - 1.98) < 0.00001)
    #expect(abs(first.transcription.words[0].start - 0.12) < 0.00001)
    #expect(first.transcription.localeIdentifier == "en_GB")
    #expect(first.transcription.engine == .system)
    #expect(first.transcription.words.allSatisfy { $0.start >= 0 && $0.end <= first.duration })
    #expect(clips[1].text == "Another phrase!")
    #expect(first.end <= clips[1].start)
    #expect(clips == PracticeClipSuggestions.clips(transcription: transcript, duration: 4))
  }

  @Test("Pauses split unpunctuated phrases and omit long silence")
  func pauses() {
    let transcript = TranscriptionResult(
      text: "one two three four",
      words: [
        word("one", 0, 0.6), word("two", 0.7, 1.4),
        word("three", 8, 8.6), word("four", 8.7, 9.4),
      ])
    let clips = PracticeClipSuggestions.clips(transcription: transcript, duration: 10)
    #expect(clips.map(\.text) == ["one two", "three four"])
    #expect(clips.allSatisfy { $0.duration < 2 })
  }

  @Test("Long uninterrupted speech splits at words into short bounded clips")
  func longSpeech() {
    let words = (0..<70).map { word("word\($0)", Double($0) * 0.5, Double($0) * 0.5 + 0.4) }
    let clips = PracticeClipSuggestions.clips(
      transcription: TranscriptionResult(text: "Speech", words: words), duration: 35)
    #expect(clips.count > 1)
    #expect(clips.allSatisfy { $0.start >= 0 && $0.end <= 35 && (1...15).contains($0.duration) })
    #expect(clips.flatMap { $0.transcription.words.map(\.word) } == words.map(\.word))
    for clip in clips {
      #expect(clip.transcription.words.allSatisfy { $0.start >= 0 && $0.end <= clip.duration })
    }
  }

  @Test("Short clips pad to one second without including neighbouring words")
  func shortPhrase() {
    let transcript = TranscriptionResult(text: "hello", words: [word("hello", 0.1, 0.5)])
    let clips = PracticeClipSuggestions.clips(transcription: transcript, duration: 1.2)
    #expect(clips.count == 1)
    #expect(clips.first?.duration == 1)
    #expect(PracticeClipSuggestions.clips(transcription: transcript, duration: 0.8).isEmpty)
  }

  @Test("A short word before a long silence does not consume the next phrase")
  func shortWordBeforeSilence() {
    let clips = PracticeClipSuggestions.clips(
      transcription: TranscriptionResult(
        text: "Yes. Another phrase.",
        words: [
          word("Yes.", 0.1, 0.5), word("Another", 20, 20.8), word("phrase.", 20.9, 21.6),
        ]), duration: 22)
    #expect(clips.map(\.text) == ["Yes.", "Another phrase."])
    #expect(clips.allSatisfy { (1...15).contains($0.duration) })
  }

  @Test("Japanese sentence endings are phrase boundaries")
  func multilingual() {
    let transcript = TranscriptionResult(
      text: "こんにちは。もう一度！",
      words: [
        word("こんにちは。", 0.2, 1.5), word("もう一度！", 1.8, 3.2),
      ], localeIdentifier: "ja_JP")
    let clips = PracticeClipSuggestions.clips(transcription: transcript, duration: 3.5)
    #expect(clips.map(\.text) == ["こんにちは。", "もう一度！"])
  }

  @Test("Missing and unsafe timestamps leave suggestions empty")
  func invalidTiming() {
    #expect(PracticeClipSuggestions.clips(transcription: nil, duration: 5).isEmpty)
    #expect(
      PracticeClipSuggestions.clips(
        transcription: TranscriptionResult(text: "No word timing", words: []), duration: 5
      ).isEmpty)
    for words in [
      [word("outside", 6, 7)],
      [word("nan", .nan, 1)], [word("infinite", 0, .infinity)],
      [word("reversed", 2, 1)], [word("", 0, 1)],
      [word("fully later", 6, 7), word("late too", 7, 8)],
    ] {
      #expect(
        PracticeClipSuggestions.clips(
          transcription: TranscriptionResult(text: "Invalid", words: words), duration: 5
        ).isEmpty)
    }
    #expect(
      PracticeClipSuggestions.clips(
        transcription: TranscriptionResult(
          text: "too long", words: [word("long", 0, 14.8)]), duration: 20
      ).isEmpty)
    #expect(
      PracticeClipSuggestions.clips(
        transcription: TranscriptionResult(text: "word", words: [word("word", 0, 1)]),
        duration: .infinity
      ).isEmpty)
  }

  @Test("Small timing errors are repaired instead of discarding every suggestion")
  func repairsSmallTimingErrors() throws {
    let overrun = PracticeClipSuggestions.clips(
      transcription: TranscriptionResult(
        text: "Hello there. Last words.",
        words: [
          word("Hello", 0.5, 1.0), word("there.", 1.1, 1.6),
          word("Last", 3.0, 3.5), word("words.", 3.6, 4.02),
        ]), duration: 4)
    #expect(overrun.map(\.text) == ["Hello there.", "Last words."])
    #expect(overrun.allSatisfy { $0.start >= 0 && $0.end <= 4 })

    let overlap = PracticeClipSuggestions.clips(
      transcription: TranscriptionResult(
        text: "one two",
        words: [word("one", 0.5, 1.5), word("two", 1.45, 2.4)]), duration: 4)
    let clip = try #require(overlap.first)
    #expect(clip.text == "one two")
    #expect(clip.transcription.words[1].start >= clip.transcription.words[0].end)

    let dropped = PracticeClipSuggestions.clips(
      transcription: TranscriptionResult(
        text: "good bad",
        words: [word("good", 0.5, 1.5), word("bad", .nan, 2)]), duration: 4)
    #expect(dropped.map(\.text) == ["good"])
  }

  private func word(_ text: String, _ start: Double, _ end: Double) -> TranscriptWord {
    TranscriptWord(word: text, start: start, end: end, confidence: 0.9)
  }
}
