import Foundation

// Sound comparison: which Reference words sounded different in a take, from the audio.
// Frozen lab method `eng_final` round 2 (build/pron-lab/proto/eng_final/final_engine.py).

/// One Reference word with its timing in seconds on the clip's own clock.
/// Untimed words (`start == nil`) get no sounds and no score.
public struct SoundWord: Codable, Sendable, Equatable {
  public var text: String
  public var start: Double?
  public var end: Double?

  public init(text: String, start: Double?, end: Double?) {
    self.text = text
    self.start = start
    self.end = end
  }

  public init(_ word: TranscriptWord) {
    self.init(text: word.word, start: word.start, end: word.end)
  }
}

/// How one take word sounds against the Reference (one per Reference word, in order).
public struct WordSoundScore: Codable, Sendable, Equatable {
  public var wordIndex: Int
  public var text: String
  /// Higher is further from the Reference. Nil when a model had no sound for the word or could
  /// not align the take. Internal: never shown as a number (N1).
  public var score: Double?
  /// Passes FR-9: at least 3 letters, Reference span ≥ 0.12 s, timed, scored.
  public var eligible: Bool
  /// Among the take's strongest eligible words (FR-8) and above the engine threshold (FR-7).
  public var flagged: Bool
  /// 1 is the strongest flag; nil when not flagged.
  public var flagRank: Int?

  public init(
    wordIndex: Int, text: String, score: Double?, eligible: Bool, flagged: Bool, flagRank: Int?
  ) {
    self.wordIndex = wordIndex
    self.text = text
    self.score = score
    self.eligible = eligible
    self.flagged = flagged
    self.flagRank = flagRank
  }
}

/// One expected sound (IPA or ARPAbet symbol of the engine's first model) as found in the take.
public struct SoundPhone: Codable, Sendable, Equatable {
  public var symbol: String
  public var wordIndex: Int
  /// Seconds on the take's clock.
  public var start: Double
  public var end: Double

  public init(symbol: String, wordIndex: Int, start: Double, end: Double) {
    self.symbol = symbol
    self.wordIndex = wordIndex
    self.start = start
    self.end = end
  }
}

/// Per Reference and model: the expected sounds (greedy decode of the Reference), their words,
/// and the Reference's own per-sound GOP-SF and margin (subtracted from the take's).
public struct ModelReferenceAnalysis: Codable, Sendable, Equatable {
  public var modelID: String
  /// Seconds cut from the start of the Reference by the silence trim.
  public var offsetSeconds: Double
  public var frames: Int
  public var phoneIDs: [Int]
  public var phones: [String]
  /// Reference word index of each sound.
  public var phoneWords: [Int]
  /// First greedy frame of each sound (trimmed clock, 20 ms frames).
  public var phoneFrames: [Int]
  /// Nil when the sounds could not be aligned to the Reference itself (or there are none).
  public var gopSF: [Double]?
  public var margin: [Double]?
  /// Viterbi spans `[first, last]` of each sound on the Reference.
  public var spans: [[Int]]?
}

/// Cacheable result of analysing a Reference: once per Reference per engine (FR-11).
public struct ReferenceAnalysis: Codable, Sendable, Equatable {
  public var engineID: String
  public var engineVersion: String
  public var words: [SoundWord]
  public var models: [ModelReferenceAnalysis]

  public init(
    engineID: String, engineVersion: String, words: [SoundWord], models: [ModelReferenceAnalysis]
  ) {
    self.engineID = engineID
    self.engineVersion = engineVersion
    self.words = words
    self.models = models
  }
}

/// One take compared with its Reference by one engine (PS-3).
public struct SoundComparisonResult: Codable, Sendable, Equatable {
  public var engineID: String
  public var engineVersion: String
  /// One entry per Reference word.
  public var words: [WordSoundScore]
  /// The Reference's sounds as aligned on the take. Empty when the take could not be aligned.
  public var phones: [SoundPhone]

  public init(
    engineID: String, engineVersion: String, words: [WordSoundScore], phones: [SoundPhone]
  ) {
    self.engineID = engineID
    self.engineVersion = engineVersion
    self.words = words
    self.phones = phones
  }

  /// Flagged words, strongest first. At most `maxFlags` (FR-8).
  public var flags: [WordSoundScore] {
    words.filter(\.flagged).sorted { ($0.flagRank ?? .max) < ($1.flagRank ?? .max) }
  }

  /// FR-21: a verdict may compare two results only from the same engine and version.
  public func isComparable(with other: SoundComparisonResult) -> Bool {
    engineID == other.engineID && engineVersion == other.engineVersion
  }
}

/// Sound comparison data kept with a take, per engine (D6). Stored in the take's analysis file.
public struct TakeSounds: Codable, Sendable, Equatable {
  /// This take against its practice's Reference, by engine id.
  public var comparisons: [String: SoundComparisonResult]
  /// This take's own analysis when it is a Reference, by engine id (FR-11 cache).
  public var referenceAnalyses: [String: ReferenceAnalysis]

  public init(
    comparisons: [String: SoundComparisonResult] = [:],
    referenceAnalyses: [String: ReferenceAnalysis] = [:]
  ) {
    self.comparisons = comparisons
    self.referenceAnalyses = referenceAnalyses
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    comparisons = try container.decodeIfPresent(
      [String: SoundComparisonResult].self, forKey: .comparisons) ?? [:]
    referenceAnalyses = try container.decodeIfPresent(
      [String: ReferenceAnalysis].self, forKey: .referenceAnalyses) ?? [:]
  }

  public var isEmpty: Bool { comparisons.isEmpty && referenceAnalyses.isEmpty }

  /// A result for `engineID` made by the current `engineVersion`, if any.
  public func comparison(engineID: String, engineVersion: String) -> SoundComparisonResult? {
    comparisons[engineID].flatMap { $0.engineVersion == engineVersion ? $0 : nil }
  }

  /// The cached Reference analysis, when it was made by this engine version for these words.
  public func referenceAnalysis(
    engineID: String, engineVersion: String, words: [SoundWord]
  ) -> ReferenceAnalysis? {
    referenceAnalyses[engineID].flatMap {
      $0.engineVersion == engineVersion && $0.words == words ? $0 : nil
    }
  }

  /// Everything one engine made (FR-27).
  public func removingEngine(_ engineID: String) -> TakeSounds {
    var copy = self
    copy.comparisons[engineID] = nil
    copy.referenceAnalyses[engineID] = nil
    return copy
  }
}

/// Frozen engine constants (`final_engine.ENGINES`).
public struct SoundComparisonConfiguration: Codable, Sendable, Equatable {
  public enum Aggregation: String, Codable, Sendable { case min, mix, bottom2 = "bot2" }

  /// Bump when the method, a constant, a model package or a front end changes. Results and
  /// cached Reference analyses from another version are not used.
  public static let engineVersion = "eng_final-r2.1"

  public var id: String
  public var models: [String]
  public var aggregation: Aggregation
  public var mixA: Double
  public var marginWeight: Double
  public var threshold: Double
  public var minLetters: Int
  public var minDurationSeconds: Double
  public var maxFlags: Int

  /// ZIPA masked fp16 + HuBERT int8 + xlsr53 int8 (519 MB).
  public static let full = SoundComparisonConfiguration(
    id: "full", models: ["zipa", "hubert8", "xlsr8"], aggregation: .mix, mixA: 0.5,
    marginWeight: 1.0, threshold: 11.837782781022973, minLetters: 3, minDurationSeconds: 0.12,
    maxFlags: 3)
  /// ZIPA masked fp16 alone (126 MB).
  public static let lite = SoundComparisonConfiguration(
    id: "lite", models: ["zipa"], aggregation: .min, mixA: 0.5, marginWeight: 1.0,
    threshold: 16.700999115413737, minLetters: 3, minDurationSeconds: 0.12, maxFlags: 3)

  public static func named(_ id: String) -> SoundComparisonConfiguration? {
    [lite, full].first { $0.id == id }
  }
}

/// `manifest.json` written by `scripts/setup-sound-comparison.sh` next to the model packages.
public struct SoundEngineManifest: Codable, Sendable, Equatable {
  public struct Model: Codable, Sendable, Equatable {
    public var id: String
    public var package: String
    public var vocabulary: String
    public var sizeBytes: Int
  }

  public var engineID: String
  public var engineVersion: String
  public var models: [Model]
  public var sizeBytes: Int

  /// True when this install matches the app's engine definition.
  public var isCurrent: Bool {
    engineVersion == SoundComparisonConfiguration.engineVersion
      && SoundComparisonConfiguration.named(engineID)?.models == models.map(\.id)
  }
}

/// Why a take gets no sound comparison (D2, FR-10, N4).
public enum SoundComparisonSkipReason: String, Sendable, Equatable {
  case noReference = "no_reference"
  case notEnglish = "not_english"
  case missingTranscript = "missing_transcript"
  case wordsDidNotLineUp = "words_did_not_line_up"
  case noisy
  case clipping

  /// Nil when the take may be compared with its Reference: both English by the word-cue rule,
  /// and today's Compare quality rules pass (noise, clipping, matched words).
  public static func check(
    reference: PracticeSession?, attempt: PracticeSession, localeIdentifier: String?
  ) -> SoundComparisonSkipReason? {
    guard let reference else { return .noReference }
    guard
      CoachingPlanner.supportsEnglishWordCues(
        reference: reference, attempt: attempt, localeIdentifier: localeIdentifier)
    else { return .notEnglish }
    switch MimicComparison.compare(reference: reference, attempt: attempt).status {
    case .ok: return nil
    case .missingTranscript: return .missingTranscript
    case .tooManyWords, .lowCoverage: return .wordsDidNotLineUp
    case .poorSnr: return .noisy
    case .clipping: return .clipping
    }
  }
}

/// An engine that compares takes with a Reference, sound by sound (FR-4).
public protocol SoundComparisonEngine {
  var id: String { get }
  var version: String { get }
  /// `samples`: 16 kHz mono.
  func analyzeReference(samples: [Float], words: [SoundWord]) throws -> ReferenceAnalysis
  /// The take's own transcript is not used: the Reference's sounds are aligned to the audio.
  func compare(reference: ReferenceAnalysis, takeSamples: [Float]) throws -> SoundComparisonResult
}

public enum SoundComparisonError: Error, Equatable {
  case referenceFromOtherEngine
  case engineNotInstalled(String)
  case unexpectedModel(String)
}
