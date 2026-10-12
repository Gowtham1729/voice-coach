import Foundation

/// Thresholds governing one-target retry cues, verdicts, and pause detection.
public enum RetryThresholds {
  // MARK: - Target Trigger / "Close Enough" Thresholds

  /// Minimum pitch delta to trigger a pitch corrective target (in semitones).
  /// Gaps below this threshold are considered "close enough" to the reference.
  public static let targetPitchSemitones: Double = 2.5

  /// Minimum loudness delta to trigger an emphasis corrective target (in dB).
  /// Gaps below this threshold are considered "close enough" to the reference.
  public static let targetLoudnessDB: Double = 3.5

  /// Minimum timing delta on a target word to warrant timing correction (in seconds).
  public static let targetWordTimingSeconds: Double = 0.25

  /// Minimum phrase drift to warrant whole-phrase pacing correction (in seconds).
  public static let targetPhraseTimingSeconds: Double = 0.25

  // MARK: - Retry Delta Thresholds ("Clearly Closer" / Verdicts)
  // Measured 2026-10-13 from session 7C181091 (7 takes) in noise.md.
  // Corresponds to 2x SD of take-to-take change, excluding one hesitation outlier.

  /// Pitch gap shrink required to earn the "closer to the reference" verdict (in semitones).
  /// 2x SD of clean take-to-take pitch change is ~2.42 st.
  public static let clearlyCloserPitchSemitones: Double = 2.5

  /// Loudness gap shrink required to earn the "closer to the reference" verdict (in dB).
  /// 2x SD of clean take-to-take loudness change is ~3.52 dB.
  public static let clearlyCloserLoudnessDB: Double = 3.5

  /// Word-duration timing shrink required to earn the "closer to the reference" verdict (in seconds).
  /// 2x SD of clean take-to-take word duration change is ~0.21 s.
  public static let clearlyCloserWordTimingSeconds: Double = 0.25

  /// Whole-phrase timing drift shrink required to earn the "closer to the reference" verdict (in seconds).
  /// 2x SD of clean take-to-take start/drift timing is ~1.68 s.
  public static let clearlyCloserPhraseTimingSeconds: Double = 1.5

  // MARK: - Plain Take Pause Floor

  /// Pauses below 0.6 s are typical syntactic / phrase-boundary pauses in conversational speech;
  /// pauses >= 0.6 s represent noticeable hesitations. Leading and trailing silences are ignored.
  public static let plainPauseFloorSeconds: Double = 0.6
}
