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

  // Tier 1 uses the plain target thresholds from the retry spec.
  public static let selectionPitchSemitones = targetPitchSemitones
  public static let selectionLoudnessDB = targetLoudnessDB

  // Tier 2 uses 2x the SD of signed selected-target gap changes in the 42
  // ordered pairs from session 7C181091. The source measurements and broader
  // all-word SDs are in /Users/gowtham/one-target-shots/noise.md; the selected
  // pair SDs are 1.341 st (36 pitch pairs) and 1.608 dB (6 loudness pairs).
  // Their doubled values are 2.682234 st and 3.216290 dB from logged gaps.
  public static let tier2PitchSemitones: Double = 2.68223431146261
  public static let tier2LoudnessDB: Double = 3.21628972575544

  /// Minimum timing delta on a target word to warrant timing correction (in seconds).
  public static let targetWordTimingSeconds: Double = 0.25

  /// Minimum phrase drift to warrant whole-phrase pacing correction (in seconds).
  /// Aligned with the measured take-to-take noise floor (~1.5 s) to avoid cueing drift within noise.
  public static let targetPhraseTimingSeconds: Double = 1.5

  // MARK: - Retry Delta Thresholds ("Clearly Closer" / Verdicts)
  // In /Users/gowtham/one-target-shots/noise.md, session 7C181091, the
  // median absolute consecutive changes are 0.88 st and 1.36 dB. The 42
  // ordered same-style pairs with the round-2 cue gates have selected-target
  // medians of 1.194 st and 1.513 dB. Use those rounded margins on top of the
  // target thresholds to avoid calling ordinary variation "closer".
  public static let retryPitchTakeToTakeMarginSemitones: Double = 1.2
  public static let retryLoudnessTakeToTakeMarginDB: Double = 1.5

  /// Pitch gap shrink required to earn the "closer to the reference" verdict (in semitones).
  public static let clearlyCloserPitchSemitones = targetPitchSemitones + retryPitchTakeToTakeMarginSemitones

  /// Loudness gap shrink required to earn the "closer to the reference" verdict (in dB).
  public static let clearlyCloserLoudnessDB = targetLoudnessDB + retryLoudnessTakeToTakeMarginDB

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
