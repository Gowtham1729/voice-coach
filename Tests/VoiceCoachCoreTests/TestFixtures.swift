import Foundation
import VoiceCoachCore

enum CoreTestFixtures {
  static func metrics(
    duration: Double = 1.5,
    snrDB: Double = 20,
    clippingPercent: Double = 0,
    internalPauseCount: Int = 0,
    meanInternalPauseMs: Double = 0
  ) -> VoiceMetrics {
    VoiceMetrics(
      duration: duration,
      activeSpeechDuration: duration,
      sampleRateHz: 16_000,
      noiseFloorDBFS: -55,
      snrDB: snrDB,
      clippingPercent: clippingPercent,
      nonSpeechRatio: 0,
      internalPauseCount: internalPauseCount,
      internalPauseTotalMs: Double(internalPauseCount) * meanInternalPauseMs,
      meanInternalPauseMs: meanInternalPauseMs,
      medianInternalPauseMs: meanInternalPauseMs,
      longestInternalPauseMs: meanInternalPauseMs,
      leadingSilenceMs: 0,
      trailingSilenceMs: 0,
      meanLoudnessDBFS: -20,
      loudnessDynamicRangeDB: 6,
      loudnessStandardDeviationDB: 1.5,
      phraseStartDBFS: -19,
      phraseEndDBFS: -21,
      phraseDecayDB: -2,
      medianPitchHz: 160,
      pitchLowHz: 145,
      pitchHighHz: 180,
      pitchVariationHz: 8,
      pitchRangeSemitones: 3.7,
      pitchStandardDeviationSemitones: 1.2,
      pitchInstabilityPercent: 2,
      hnrDB: 18,
      cppDB: 12
    )
  }

  static func analysis(
    duration: Double = 1.5,
    snrDB: Double = 20,
    clippingPercent: Double = 0
  ) -> AnalysisResult {
    AnalysisResult(
      metrics: metrics(duration: duration, snrDB: snrDB, clippingPercent: clippingPercent),
      loudnessContour: [TimePoint(time: 0.2, value: -20), TimePoint(time: 1.2, value: -22)],
      pitchContour: [TimePoint(time: 0.2, value: 155), TimePoint(time: 1.2, value: 165)],
      waveform: [WaveformPoint(minimum: -0.4, maximum: 0.4)],
      spectrogram: SpectrogramData(columns: 1, rows: 1, decibels: [-30])
    )
  }

  static func session(
    words: [String] = ["clear", "steady", "voice"],
    snrDB: Double = 20,
    clippingPercent: Double = 0
  ) -> PracticeSession {
    let transcriptWords = words.enumerated().map { index, word in
      TranscriptWord(
        word: word,
        start: Double(index) * 0.35,
        end: Double(index) * 0.35 + 0.25,
        confidence: 0.98
      )
    }
    let analyses = transcriptWords.enumerated().map { index, word in
      WordAnalysis(
        word: word.word,
        start: word.start,
        end: word.end,
        pitch: WordPitchMetrics(
          medianHz: 155 + Double(index) * 5,
          relativeMedianSemitones: Double(index),
          rangeSemitones: 2,
          startToEndSemitones: 0.5,
          validPitchFrames: 10,
          pitchCoverage: 1
        ),
        loudness: WordLoudnessMetrics(
          relativeMeanDB: Double(index) - 1,
          startToEndDB: -0.5,
          activeFrameCoverage: 1
        )
      )
    }
    return PracticeSession(
      audioURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).wav"),
      result: analysis(snrDB: snrDB, clippingPercent: clippingPercent),
      transcription: TranscriptionResult(
        text: words.joined(separator: " "), words: transcriptWords),
      words: analyses
    )
  }
}
