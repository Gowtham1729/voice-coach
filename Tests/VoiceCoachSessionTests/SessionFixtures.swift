import Foundation
import VoiceCoachCore
import VoiceCoachSession

enum SessionTestFixtures {
  static func analysis(duration: Double = 2) -> AnalysisResult {
    AnalysisResult(
      metrics: VoiceMetrics(
        duration: duration,
        activeSpeechDuration: duration,
        sampleRateHz: 16_000,
        noiseFloorDBFS: -55,
        snrDB: 20,
        clippingPercent: 0,
        nonSpeechRatio: 0,
        internalPauseCount: 0,
        internalPauseTotalMs: 0,
        meanInternalPauseMs: 0,
        medianInternalPauseMs: 0,
        longestInternalPauseMs: 0,
        leadingSilenceMs: 0,
        trailingSilenceMs: 0,
        meanLoudnessDBFS: -20,
        loudnessDynamicRangeDB: 5,
        loudnessStandardDeviationDB: 1,
        phraseStartDBFS: -20,
        phraseEndDBFS: -21,
        phraseDecayDB: -1,
        medianPitchHz: 160,
        pitchLowHz: 150,
        pitchHighHz: 175,
        pitchVariationHz: 7,
        pitchRangeSemitones: 2.7,
        pitchStandardDeviationSemitones: 1,
        pitchInstabilityPercent: 2,
        hnrDB: 18,
        cppDB: 11
      ),
      loudnessContour: [TimePoint(time: 0.5, value: -20)],
      pitchContour: [TimePoint(time: 0.5, value: 160)],
      waveform: [WaveformPoint(minimum: -0.3, maximum: 0.3)],
      spectrogram: SpectrogramData(columns: 1, rows: 1, decibels: [-25])
    )
  }

  static func take(id: UUID = UUID(), audioURL: URL, duration: Double = 2) -> PracticeSession {
    PracticeSession(
      id: id,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      audioURL: audioURL,
      result: analysis(duration: duration)
    )
  }

  static func session(
    id: UUID = UUID(),
    take: PracticeSession,
    mode: PracticeMode = .general,
    archived: Bool = false
  ) -> CoachingSession {
    CoachingSession(
      id: id,
      name: "Practice",
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
      mode: mode,
      prompt: "",
      keepsRecordings: true,
      takes: [take],
      archived: archived
    )
  }

  static func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("VoiceCoachSessionTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
