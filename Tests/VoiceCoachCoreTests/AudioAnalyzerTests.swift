import Foundation
import Testing
import VoiceCoachCore

@Suite("Audio analyzer")
struct AudioAnalyzerTests {
  @Test("Empty input returns a stable empty result")
  func emptyInput() {
    let result = AudioAnalyzer().analyze(samples: [], sampleRate: 16_000)

    #expect(result.metrics.duration == 0)
    #expect(result.pitchContour.isEmpty)
    #expect(result.waveform.isEmpty)
  }

  @Test("Steady voiced input produces bounded pitch and duration")
  func steadyTone() {
    let sampleRate = 16_000.0
    let samples = (0..<Int(sampleRate * 1.2)).map { index in
      Float(0.35 * sin(2 * .pi * 160 * Double(index) / sampleRate))
    }

    let result = AudioAnalyzer().analyze(samples: samples, sampleRate: sampleRate)

    #expect(abs(result.metrics.duration - 1.2) < 0.001)
    #expect(result.metrics.medianPitchHz != nil)
    #expect(abs((result.metrics.medianPitchHz ?? 0) - 160) < 12)
    #expect(result.acousticFrames.pitch.count >= result.pitchContour.count)
  }

  @Test("A pitch jump across a pause is not frame-level instability")
  func instabilityIgnoresPauses() throws {
    let sampleRate = 16_000.0
    func tone(_ frequency: Double, seconds: Double) -> [Float] {
      (0..<Int(sampleRate * seconds)).map { index in
        Float(0.35 * sin(2 * .pi * frequency * Double(index) / sampleRate))
      }
    }
    let silence = [Float](repeating: 0, count: Int(sampleRate * 0.5))

    let steady = AudioAnalyzer().analyze(
      samples: tone(120, seconds: 1), sampleRate: sampleRate)
    let twoPhrases = AudioAnalyzer().analyze(
      samples: tone(120, seconds: 1) + silence + tone(220, seconds: 1), sampleRate: sampleRate)

    let steadyInstability = try #require(steady.metrics.pitchInstabilityPercent)
    let splitInstability = try #require(twoPhrases.metrics.pitchInstabilityPercent)
    #expect(steadyInstability < 1)
    #expect(splitInstability < 1)
  }

  @Test("A word whose end precedes its start yields empty metrics instead of trapping")
  func reversedWordBounds() {
    let sampleRate = 16_000.0
    let samples = (0..<Int(sampleRate)).map { index in
      Float(0.35 * sin(2 * .pi * 160 * Double(index) / sampleRate))
    }
    let result = AudioAnalyzer().analyze(samples: samples, sampleRate: sampleRate)
    let transcription = TranscriptionResult(
      text: "backwards",
      words: [TranscriptWord(word: "backwards", start: 0.8, end: 0.2, confidence: nil)])

    let words = WordAcousticAnalyzer().analyze(transcription: transcription, result: result)

    #expect(words.count == 1)
    #expect(words.first?.pitch.medianHz == nil)
  }
}
