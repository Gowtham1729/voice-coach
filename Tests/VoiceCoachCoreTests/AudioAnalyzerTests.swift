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
}
