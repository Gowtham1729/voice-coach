import Foundation

// Sound comparison: which Reference words sounded different in a take, from the audio.
// Frozen lab method `eng_r3` round 3 (build/pron-lab/proto/eng_r3/final_engine_r3.py, on top of
// eng_final/final_engine.py).

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

/// The Reference's ZIPA encoder frames inside each timed word, for the word DTW (eng_r3). Already
/// standardised over the trimmed Reference and L2-normalised, stored as IEEE half floats: about
/// 1 KB per 20 ms of word audio (≈ 50 KB per second, base64 in JSON).
public struct ReferenceWordFrames: Codable, Sendable, Equatable {
  /// Values per frame (512 for ZIPA small).
  public var dimension: Int
  /// Frames stored for each Reference word, in order. 0: the word gets no DTW cost.
  public var frameCounts: [Int]
  /// Little-endian Float16 values, word after word, frame after frame.
  public var values: Data

  public init(dimension: Int, frameCounts: [Int], values: Data) {
    self.dimension = dimension
    self.frameCounts = frameCounts
    self.values = values
  }
}

/// Cacheable result of analysing a Reference: once per Reference per engine (FR-11).
public struct ReferenceAnalysis: Codable, Sendable, Equatable {
  public var engineID: String
  public var engineVersion: String
  public var words: [SoundWord]
  public var models: [ModelReferenceAnalysis]
  /// Nil when the engine uses no word DTW or the first model has no encoder output.
  public var wordFrames: ReferenceWordFrames?

  public init(
    engineID: String, engineVersion: String, words: [SoundWord], models: [ModelReferenceAnalysis],
    wordFrames: ReferenceWordFrames? = nil
  ) {
    self.engineID = engineID
    self.engineVersion = engineVersion
    self.words = words
    self.models = models
    self.wordFrames = wordFrames
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

  /// Where a Reference word was found in the take (take clock), from its aligned sounds.
  /// Nil when the take could not be aligned or the word has no sounds.
  public func takeSpan(wordIndex: Int) -> ClosedRange<Double>? {
    let sounds = phones.filter { $0.wordIndex == wordIndex }
    guard let start = sounds.map(\.start).min(), let end = sounds.map(\.end).max(), end > start
    else { return nil }
    return start...end
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

/// Frozen engine constants (`final_engine_r3.ENGINES`).
public struct SoundComparisonConfiguration: Codable, Sendable, Equatable {
  public enum Aggregation: String, Codable, Sendable { case min, mix, bottom2 = "bot2" }

  /// Bump when the method, a constant, a model package or a front end changes. Results and
  /// cached Reference analyses from another version are not used.
  public static let engineVersion = "eng_r3"

  public var id: String
  public var models: [String]
  public var aggregation: Aggregation
  public var mixA: Double
  public var marginWeight: Double
  public var threshold: Double
  public var minLetters: Int
  public var minDurationSeconds: Double
  public var maxFlags: Int
  /// RPS: GOP-SF substitutes only the sounds each model's substitution table allows.
  public var restrictedSubstitutions: Bool
  /// Speaker-relative shift: word score −= `relativeShift` × median of the take's word scores.
  public var relativeShift: Double
  /// Second key: word score += `dtwWeight` × (ZIPA-encoder DTW cost − `dtwCenter`). 0: no DTW.
  public var dtwWeight: Double
  public var dtwCenter: Double

  /// `full_r3`: ZIPA masked fp16 + HuBERT int8 + xlsr53 int8 (519 MB).
  public static let full = SoundComparisonConfiguration(
    id: "full", models: ["zipa", "hubert8", "xlsr8"], aggregation: .mix, mixA: 0.5,
    marginWeight: 1.0, threshold: 11.330850476804837, minLetters: 3, minDurationSeconds: 0.12,
    maxFlags: 3, restrictedSubstitutions: true, relativeShift: 0.2, dtwWeight: 2.0, dtwCenter: 0)
  /// `lite_r3`: ZIPA masked fp16 alone (126 MB).
  public static let lite = SoundComparisonConfiguration(
    id: "lite", models: ["zipa"], aggregation: .min, mixA: 0.5, marginWeight: 1.0,
    threshold: 21.72401620754543, minLetters: 3, minDurationSeconds: 0.12, maxFlags: 3,
    restrictedSubstitutions: false, relativeShift: 0, dtwWeight: 24.0, dtwCenter: 0.74)

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
    /// `<model>-substitutions.json` (engines with restricted substitutions only).
    public var substitutions: String?
    public var sizeBytes: Int
  }

  public var engineID: String
  public var engineVersion: String
  public var models: [Model]
  public var sizeBytes: Int

  /// True when this install matches the app's engine definition.
  public var isCurrent: Bool {
    guard engineVersion == SoundComparisonConfiguration.engineVersion,
      let configuration = SoundComparisonConfiguration.named(engineID),
      configuration.models == models.map(\.id)
    else { return false }
    return !configuration.restrictedSubstitutions || models.allSatisfy { $0.substitutions != nil }
  }
}

/// Why a take gets no sound comparison (D2, FR-10, N4).
public enum SoundComparisonSkipReason: String, Sendable, Equatable {
  case noReference = "no_reference"
  /// The Reference's audio file is gone or cannot be read: a retry cannot help.
  case referenceAudioMissing = "reference_audio_missing"
  /// The take's audio file is gone or cannot be read.
  case takeAudioMissing = "take_audio_missing"
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
  /// The Reference's sounds are aligned to the take's audio. `takeWords` (one per Reference
  /// word, take clock, nil when unmatched) only place the word DTW; see
  /// `SoundComparisonWordMap.takeWords`.
  func compare(reference: ReferenceAnalysis, takeSamples: [Float], takeWords: [SoundWord?]) throws
    -> SoundComparisonResult
}

/// Which take word stands for each Reference word, for the word DTW (eng_r3 `take_words`).
public enum SoundComparisonWordMap {
  /// One entry per Reference transcript word: the take word the transcripts matched, or the
  /// single take word between two matches (or a match and an edge) when exactly one Reference
  /// word sits there too. Nil otherwise.
  public static func takeWords(reference: PracticeSession, attempt: PracticeSession) -> [SoundWord?]
  {
    let referenceWords = reference.transcription?.words ?? []
    let attemptWords = attempt.transcription?.words ?? []
    var map = [SoundWord?](repeating: nil, count: referenceWords.count)
    let pairs = MimicComparison.compare(reference: reference, attempt: attempt).pairs
      .map { ($0.referenceIndex, $0.attemptIndex) }
    for (a, b) in pairs { map[a] = SoundWord(attemptWords[b]) }
    let anchors = [(-1, -1)] + pairs + [(referenceWords.count, attemptWords.count)]
    for (before, after) in zip(anchors, anchors.dropFirst())
    where after.0 - before.0 == 2 && after.1 - before.1 == 2 {
      map[before.0 + 1] = SoundWord(attemptWords[before.1 + 1])
    }
    return map
  }
}

public enum SoundComparisonError: Error, Equatable {
  case referenceFromOtherEngine
  case engineNotInstalled(String)
  case unexpectedModel(String)
  /// A substitution table made for another vocabulary.
  case substitutionTableMismatch(String)
  /// An audio file is missing or cannot be decoded.
  case unreadableAudio
}
