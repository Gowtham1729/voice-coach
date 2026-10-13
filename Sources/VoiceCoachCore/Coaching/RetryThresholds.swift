import Foundation

/// Thresholds governing one-target retry cues, verdicts, and pause detection.
public enum RetryThresholds {
  // Hysteresis margins are the median absolute take-to-take changes measured in
  // /Users/gowtham/one-target-shots/noise.md, session 7C181091 (7 takes).
  public static let closePitchMarginSemitones: Double = 0.9
  public static let closeLoudnessMarginDB: Double = 1.4
  public static let closeWordTimingMarginSeconds: Double = 0.06
  // MARK: - Target Trigger / "Close Enough" Thresholds

  /// Minimum pitch delta to trigger a pitch corrective target (in semitones).
  /// Gaps below this threshold are considered "close enough" to the reference.
  public static let targetPitchSemitones: Double = 2.5

  /// Minimum loudness delta to trigger an emphasis corrective target (in dB).
  /// Gaps below this threshold are considered "close enough" to the reference.
  public static let targetLoudnessDB: Double = 3.5

  // Selection uses a stricter pitch margin than the close-enough hysteresis.
  // In /Users/gowtham/one-target-shots/noise.md, session 7C181091, a 6.124 st
  // starting gap earned a false closer verdict across ordinary takes; the
  // deliberate word edit starts at 6.417 st. Keep that edit eligible at 6.2 st.
  public static let selectionPitchMarginSemitones: Double = 3.7
  public static let selectionPitchSemitones = targetPitchSemitones + selectionPitchMarginSemitones
  // The same session's 5.983 and 6.876 dB starting gaps yielded false close
  // or closer verdicts across ordinary takes. Require a 6.9 dB selection gap.
  public static let selectionLoudnessMarginDB: Double = 3.4
  public static let selectionLoudnessDB = targetLoudnessDB + selectionLoudnessMarginDB

  /// Minimum timing delta on a target word to warrant timing correction (in seconds).
  public static let targetWordTimingSeconds: Double = 0.25

  /// Minimum phrase drift to warrant whole-phrase pacing correction (in seconds).
  /// Aligned with the measured take-to-take noise floor (~1.5 s) to avoid cueing drift within noise.
  public static let targetPhraseTimingSeconds: Double = 1.5

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
