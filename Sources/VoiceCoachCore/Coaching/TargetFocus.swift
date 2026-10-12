import Foundation

/// The acoustic dimension targeted by a coaching cue.
public enum TargetKind: String, Codable, Sendable, Equatable {
  case pitch
  case loudness
  /// Retained to decode earlier saved targets; new targets are word pitch/loudness only.
  case timing
}

/// A focused target selected for one-target coaching and retry pinning.
public struct TargetFocus: Codable, Sendable, Equatable {
  /// Index of the target word in the reference take.
  public let referenceWordIndex: Int
  /// The word (or phrase anchor) targeted.
  public let word: String
  /// Dimension targeted: pitch, loudness, or timing.
  public let kind: TargetKind
  /// Distance from the reference (in semitones, dB, or seconds).
  public let gap: Double
  /// Time range of the target in the reference take.
  public let referenceRange: ClosedRange<Double>
  /// Time range of the target in the attempt take.
  public let takeRange: ClosedRange<Double>
  /// Whether this target represents a phrase-level pattern or a single word.
  public let isPhrase: Bool

  public init(
    referenceWordIndex: Int,
    word: String,
    kind: TargetKind,
    gap: Double,
    referenceRange: ClosedRange<Double>,
    takeRange: ClosedRange<Double>,
    isPhrase: Bool = false
  ) {
    self.referenceWordIndex = referenceWordIndex
    self.word = word
    self.kind = kind
    self.gap = gap
    self.referenceRange = referenceRange
    self.takeRange = takeRange
    self.isPhrase = isPhrase
  }
}

/// Convenience alias for the target saved on a take for subsequent retries.
public typealias SavedTarget = TargetFocus

/// Evaluation verdict for a retry attempt against a pinned target.
public enum RetryVerdict: String, Codable, Sendable, Equatable {
  /// Gap shrank by at least the measured threshold ("clearly closer").
  case held
  /// Gap fell below the target threshold ("close enough").
  case closeEnough = "close-enough"
  /// Gap change was within natural take-to-take variation noise.
  case withinNoise = "within-noise"
  /// Gap moved away by at least the measured threshold.
  case otherWay = "other-way"
  /// Recording or alignment gates did not support a verdict.
  case unreliable
  /// Target word could not be aligned in this retry take.
  case notFound = "not-found"

  /// True when the retry clearly closed the gap or reached the close band.
  public var isHeld: Bool {
    self == .held || self == .closeEnough
  }
}

/// Outcome of evaluating a retry take against a pinned target.
public struct RetryEvaluation: Codable, Sendable, Equatable {
  public let target: TargetFocus
  public let verdict: RetryVerdict
  public let newGap: Double?
  public let newTakeRange: ClosedRange<Double>?
  public let verdictCopy: String?
  public let cueCopy: String

  public init(
    target: TargetFocus,
    verdict: RetryVerdict,
    newGap: Double? = nil,
    newTakeRange: ClosedRange<Double>? = nil,
    verdictCopy: String? = nil,
    cueCopy: String
  ) {
    self.target = target
    self.verdict = verdict
    self.newGap = newGap
    self.newTakeRange = newTakeRange
    self.verdictCopy = verdictCopy
    self.cueCopy = cueCopy
  }
}

/// Descriptive cue for plain (unreferenced) takes, highlighting the longest hesitation.
public struct PlainTakeCue: Codable, Sendable, Equatable {
  /// The word immediately following the pause.
  public let followingWord: String
  /// Index of the following word in the take's transcript.
  public let followingWordIndex: Int
  /// Duration of the silent gap in seconds.
  public let pauseDurationSeconds: Double
  /// Time span of the pause itself (previousWord.end ... followingWord.start).
  public let pauseRange: ClosedRange<Double>
  /// Time span of the pause plus following word (previousWord.end ... followingWord.end).
  public let cueSpanRange: ClosedRange<Double>
  /// Playback span including +/- 150 ms padding.
  public let playbackRange: ClosedRange<Double>
  /// Locked copy text, e.g. "You paused before ‘about’."
  public let cueText: String

  public init(
    followingWord: String,
    followingWordIndex: Int,
    pauseDurationSeconds: Double,
    pauseRange: ClosedRange<Double>,
    cueSpanRange: ClosedRange<Double>,
    playbackRange: ClosedRange<Double>,
    cueText: String
  ) {
    self.followingWord = followingWord
    self.followingWordIndex = followingWordIndex
    self.pauseDurationSeconds = pauseDurationSeconds
    self.pauseRange = pauseRange
    self.cueSpanRange = cueSpanRange
    self.playbackRange = playbackRange
    self.cueText = cueText
  }
}
