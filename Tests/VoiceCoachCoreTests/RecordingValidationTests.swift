import Foundation
import Testing
import VoiceCoachCore

@Suite("Recording validation")
struct RecordingValidationTests {
  @Test("Silent audio stays analyzable but cannot be saved")
  func silence() {
    let result = AudioAnalyzer().analyze(
      samples: Array(repeating: 0, count: 16_000), sampleRate: 16_000)
    #expect(result.metrics.duration == 1)
    #expect(throws: AnalysisError.self) { try RecordingValidation.validateAudio(result) }
  }

  @Test("Quiet audio does not require tracked pitch or active speech")
  func quietAudio() throws {
    let result = AudioAnalyzer().analyze(
      samples: Array(repeating: 0.0005, count: 16_000), sampleRate: 16_000)
    #expect(result.metrics.activeSpeechDuration == 0)
    #expect(result.pitchContour.isEmpty)
    try RecordingValidation.validateAudio(result)
  }

  @Test("Blank transcription is rejected", arguments: ["", " \n\t "])
  func blankTranscript(text: String) {
    #expect(throws: TranscriptionError.self) {
      try RecordingValidation.validateTranscription(TranscriptionResult(text: text, words: []))
    }
  }

  @Test("Text without word timestamps and words without joined text are usable")
  func transcriptFallbacks() throws {
    try RecordingValidation.validateTranscription(TranscriptionResult(text: "Hello", words: []))
    try RecordingValidation.validateTranscription(
      TranscriptionResult(text: "", words: [TranscriptWord(word: "Hello", start: 0, end: 1)]))
  }

  @Test("Parakeet empty success is distinct from malformed output")
  func parakeetOutput() throws {
    do {
      _ = try NemoSpeechTranscriber.parseOutput(Data(#"{"text":"","words":[]}"#.utf8))
      Issue.record("Empty successful output must fail")
    } catch TranscriptionError.noSpeechRecognized {
    }
    do {
      _ = try NemoSpeechTranscriber.parseOutput(
        Data(#"{"text":" ","words":[{"word":" ","start":0,"end":1}]}"#.utf8))
      Issue.record("Whitespace-only output must fail as no speech")
    } catch TranscriptionError.noSpeechRecognized {
    }
    do {
      _ = try NemoSpeechTranscriber.parseOutput(Data(#"{"text":"","words":[{}]}"#.utf8))
      Issue.record("Malformed output must fail")
    } catch TranscriptionError.invalidOutput {
    }
    #expect(throws: TranscriptionError.self) {
      _ = try NemoSpeechTranscriber.parseOutput(Data("not json".utf8))
    }
  }
}
