import Dispatch
import Foundation

/// Row-major `[rows × columns]` Float matrix: one row per frame (fbank frames or logits).
public struct FrameMatrix: Sendable, Equatable {
  public let rows: Int
  public let columns: Int
  public var values: [Float]

  public init(rows: Int, columns: Int, values: [Float]) {
    precondition(values.count == rows * columns, "values.count must equal rows × columns")
    self.rows = rows
    self.columns = columns
    self.values = values
  }

  public init(rows: Int, columns: Int, repeating value: Float = 0) {
    self.init(rows: rows, columns: columns, values: [Float](repeating: value, count: rows * columns))
  }

  public subscript(row: Int, column: Int) -> Float {
    get { values[row * columns + column] }
    set { values[row * columns + column] = newValue }
  }

  public func row(_ row: Int) -> ArraySlice<Float> {
    values[(row * columns)..<((row + 1) * columns)]
  }
}

/// CTC token inventory of a phone model.
public struct PhoneVocabulary: Sendable, Equatable {
  public let tokens: [String]
  public let blank: Int
  /// Tokens that are never sounds (word marker, `<unk>`, `<pad>`…). Scoring folds them into blank.
  public let specials: Set<Int>

  static let specialSymbols: Set<String> = [
    "|", "<s>", "</s>", "<unk>", "<pad>", "[UNK]", "[PAD]", "<sos/eos>", "▁", "",
  ]

  public init(tokens: [String], blank: Int) {
    self.tokens = tokens
    self.blank = blank
    specials = Set(
      tokens.indices.filter { i in
        i != blank
          && (Self.specialSymbols.contains(tokens[i])
            || (tokens[i].hasPrefix("<") && tokens[i].hasSuffix(">")))
      })
  }

  /// `{"blank": n, "tokens": [...]}` as the setup script writes it.
  public init(contentsOf url: URL) throws {
    struct File: Decodable {
      let blank: Int
      let tokens: [String]
    }
    let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    self.init(tokens: file.tokens, blank: file.blank)
  }
}

/// A phone model that turns 16 kHz speech into raw CTC logits at 20 ms per frame.
public protocol PhoneLogitModel {
  var modelID: String { get }
  var vocabulary: PhoneVocabulary { get }
  func rawLogits(samples: [Float]) throws -> FrameMatrix
}

/// `lite` / `full`: trim silence, run each phone model on the speech only, score with
/// `SoundComparisonScoring`. Platform-free: Core ML runners live in `PhoneModelRunners.swift`.
public final class PhoneModelSoundComparisonEngine: SoundComparisonEngine {
  public let configuration: SoundComparisonConfiguration
  public let models: [any PhoneLogitModel]
  public var id: String { configuration.id }
  public var version: String { SoundComparisonConfiguration.engineVersion }

  public init(configuration: SoundComparisonConfiguration, models: [any PhoneLogitModel]) throws {
    guard models.map(\.modelID) == configuration.models else {
      throw SoundComparisonError.unexpectedModel(models.map(\.modelID).joined(separator: ","))
    }
    self.configuration = configuration
    self.models = models
  }

  public func analyzeReference(samples: [Float], words: [SoundWord]) throws -> ReferenceAnalysis {
    let (speech, offset) = SpeechTrim.trim(samples)
    let analyses = try models.map { model in
      SoundComparisonScoring.analyzeReference(
        modelID: model.modelID, logits: try model.rawLogits(samples: speech),
        offsetSeconds: offset, vocabulary: model.vocabulary, words: words)
    }
    return ReferenceAnalysis(engineID: id, engineVersion: version, words: words, models: analyses)
  }

  public func compare(reference: ReferenceAnalysis, takeSamples: [Float]) throws
    -> SoundComparisonResult
  {
    guard reference.engineID == id, reference.engineVersion == version,
      reference.models.map(\.modelID) == configuration.models
    else { throw SoundComparisonError.referenceFromOtherEngine }
    let (speech, offset) = SpeechTrim.trim(takeSamples)
    var columns: [[Double?]] = []
    var phones: [SoundPhone] = []
    for (model, analysis) in zip(models, reference.models) {
      let scored = SoundComparisonScoring.modelWordScores(
        reference: analysis, wordCount: reference.words.count,
        takeLogits: try model.rawLogits(samples: speech), vocabulary: model.vocabulary,
        configuration: configuration)
      columns.append(scored.scores)
      if phones.isEmpty, let spans = scored.spans {
        let hop = SoundComparisonScoring.hopSeconds
        phones = zip(spans.indices, spans).map { k, span in
          SoundPhone(
            symbol: analysis.phones[k], wordIndex: analysis.phoneWords[k],
            start: offset + Double(span.lowerBound) * hop,
            end: offset + Double(span.upperBound + 1) * hop)
        }
      }
    }
    return SoundComparisonResult(
      engineID: id, engineVersion: version,
      words: SoundComparisonScoring.wordScores(
        fused: SoundComparisonScoring.fuse(columns), words: reference.words, configuration),
      phones: phones)
  }
}

/// `final_engine.speech_bounds` / `trim`: librosa-style trim at 35 dB below the loudest
/// 400-sample frame (hop 160, centred), plus 50 ms each side.
public enum SpeechTrim {
  public static let topDB = 35.0
  public static let frame = 400
  public static let hop = 160
  public static let pad = 800

  public static func bounds(_ a: [Float]) -> Range<Int> {
    let n = a.count
    if n == 0 { return 0..<0 }
    let frames = 1 + n / hop
    var rms = [Double](repeating: 0, count: frames)
    for i in 0..<frames {
      var sum = 0.0
      for j in 0..<frame {
        let k = i * hop + j - frame / 2
        if k >= 0, k < n {
          let x = Double(a[k])
          sum += x * x
        }
      }
      rms[i] = (sum / Double(frame)).squareRoot()
    }
    let ref = 20 * log10(max(1e-5, rms.max() ?? 0))
    let loud = rms.indices.filter { 20 * log10(max(1e-5, rms[$0])) - ref > -topDB }
    guard let first = loud.first, let last = loud.last else { return 0..<min(n, pad) }
    return max(0, first * hop - pad)..<min(n, min(n, (last + 1) * hop) + pad)
  }

  /// (speech samples, offset seconds). Falls back to the whole clip under 0.1 s of speech.
  public static func trim(_ a: [Float]) -> (samples: [Float], offsetSeconds: Double) {
    var r = bounds(a)
    if r.count < 16_000 / 10 { r = 0..<a.count }
    return (Array(a[r]), Double(r.lowerBound) / 16_000)
  }
}

/// Row-major `[rows × columns]` Double matrix of folded log-posteriors (scoring runs in Double,
/// like eng_final's float64 numpy).
struct LogPosteriors: Sendable {
  let rows: Int
  let columns: Int
  var values: [Double]

  @inline(__always) subscript(t: Int, c: Int) -> Double { values[t * columns + c] }
}

/// Port of the scoring in `proto/eng_final/final_engine.py` (frozen, round 2). Model-independent:
/// takes raw logits of the trimmed audio. Every constant and tie rule matches the Python.
public enum SoundComparisonScoring {
  public static let hopSeconds = 0.02
  static let candidateLogProb = -8.0  // CAND_LP
  static let maxCandidates = 40  // MAX_CAND
  static let gopFloor = -30.0  // GOP_FLOOR
  static let neg = -1e30  // NEG

  // MARK: log-softmax + fold (log_softmax, fold_specials)

  static func foldedLogPosteriors(_ logits: FrameMatrix, vocabulary v: PhoneVocabulary)
    -> LogPosteriors
  {
    let rowCount = logits.rows
    let width = logits.columns
    var out = [Double](repeating: 0, count: rowCount * width)
    let fold = v.specials.sorted()
    for t in 0..<rowCount {
      let base = t * width
      var m = -Double.infinity
      for c in 0..<width { m = max(m, Double(logits.values[base + c])) }
      var sum = 0.0
      for c in 0..<width { sum += exp(Double(logits.values[base + c]) - m) }
      let shift = m + log(sum)
      for c in 0..<width { out[base + c] = Double(logits.values[base + c]) - shift }
      if !fold.isEmpty {
        var r = out[base + fold[0]]
        for c in fold.dropFirst() { r = logAddExp(r, out[base + c]) }
        out[base + v.blank] = logAddExp(out[base + v.blank], r)
        for c in fold { out[base + c] = neg }
      }
    }
    return LogPosteriors(rows: rowCount, columns: width, values: out)
  }

  /// numpy `logaddexp` (also for -inf).
  @inline(__always) static func logAddExp(_ a: Double, _ b: Double) -> Double {
    if a == -.infinity { return b }
    if b == -.infinity { return a }
    return max(a, b) + log1p(exp(-abs(a - b)))
  }

  // MARK: greedy + assign_words

  /// Greedy CTC: token ids and the first frame of each (argmax ties go to the lowest id).
  static func greedy(_ lp: LogPosteriors, blank: Int) -> (tokens: [Int], frames: [Int]) {
    var tokens: [Int] = []
    var frames: [Int] = []
    var previous = -1
    for t in 0..<lp.rows {
      var best = 0
      var bestValue = lp[t, 0]
      for c in 1..<lp.columns where lp[t, c] > bestValue {
        best = c
        bestValue = lp[t, c]
      }
      if best != previous, best != blank {
        tokens.append(best)
        frames.append(t)
      }
      previous = best
    }
    return (tokens, frames)
  }

  /// Reference word of each token: the word whose span holds the frame centre
  /// `(f + 0.5)·hop` (trimmed clock; word times shifted by `offset`), else the nearest word.
  /// Untimed words are skipped; ties go to the earlier word.
  static func assignWords(frames: [Int], words: [SoundWord], offset: Double) -> [Int?] {
    let spans = words.enumerated().compactMap { i, w -> (Int, Double, Double)? in
      guard let s = w.start, let e = w.end else { return nil }
      return (i, s - offset, e - offset)
    }
    return frames.map { f in
      let t = (Double(f) + 0.5) * hopSeconds
      var best: Int?
      var bestDistance = 1e18
      for (i, s, e) in spans {
        let d = (s <= t && t <= e) ? 0.0 : min(abs(t - s), abs(t - e))
        if d < bestDistance {
          best = i
          bestDistance = d
        }
      }
      return best
    }
  }

  // MARK: Viterbi (viterbi_align, regions)

  /// Per-token inclusive frame span of the best CTC path. Ties: stay > s−1 > s−2.
  static func viterbiAlign(_ lp: LogPosteriors, seq: [Int], blank: Int) -> [ClosedRange<Int>]? {
    let frameCount = lp.rows
    let length = seq.count
    let repeats = zip(seq, seq.dropFirst()).filter { $0 == $1 }.count
    if length == 0 || frameCount < length + repeats { return nil }
    var ext = [blank]
    for s in seq { ext += [s, blank] }
    let states = ext.count
    let skip = (0..<states).map { s in s >= 2 && ext[s] != blank && ext[s] != ext[s - 2] }
    var delta = [Double](repeating: neg, count: states)
    delta[0] = lp[0, ext[0]]
    delta[1] = lp[0, ext[1]]
    var next = delta
    var back = [UInt8](repeating: 0, count: frameCount * states)
    for t in 1..<frameCount {
      for s in 0..<states {
        let c1 = s >= 1 ? delta[s - 1] : neg
        let c2 = skip[s] ? delta[s - 2] : neg
        var arg: UInt8 = 0
        var v = delta[s]
        if c1 > v {
          arg = 1
          v = c1
        }
        if c2 > v {
          arg = 2
          v = c2
        }
        next[s] = v + lp[t, ext[s]]
        back[t * states + s] = arg
      }
      swap(&delta, &next)
    }
    var s = delta[states - 1] >= delta[states - 2] ? states - 1 : states - 2
    if delta[s] <= neg / 2 { return nil }
    var first = [Int](repeating: -1, count: length)
    var last = first
    for t in stride(from: frameCount - 1, through: 0, by: -1) {
      if s % 2 == 1 {
        let k = s / 2
        first[k] = t
        if last[k] < 0 { last[k] = t }
      }
      s -= Int(back[t * states + s])
    }
    if first.contains(where: { $0 < 0 }) { return nil }
    return (0..<length).map { first[$0]...last[$0] }
  }

  /// Each span widened halfway into the blank gaps around it.
  static func regions(_ spans: [ClosedRange<Int>], frames: Int) -> [ClosedRange<Int>] {
    spans.indices.map { i in
      let s = spans[i].lowerBound
      let e = spans[i].upperBound
      let lo = i == 0 ? 0 : (spans[i - 1].upperBound + s) / 2 + 1
      let hi = i == spans.count - 1 ? frames - 1 : (e + spans[i + 1].lowerBound) / 2
      return min(lo, s)...max(hi, e)
    }
  }

  // MARK: CTC forward (ctc_loglik_batch, one sequence)

  /// log P(seq | frames `window` of lp), standard CTC; -inf when infeasible.
  static func ctcLogLikelihood(
    _ lp: LogPosteriors, window: ClosedRange<Int>, seq: [Int], blank: Int,
    alpha: inout [Double], next: inout [Double]
  ) -> Double {
    let stateCount = 2 * seq.count + 1
    if alpha.count < stateCount {
      alpha = [Double](repeating: 0, count: stateCount)
      next = alpha
    }
    @inline(__always) func ext(_ s: Int) -> Int { s % 2 == 0 ? blank : seq[s / 2] }
    let t0 = window.lowerBound
    for s in 0..<stateCount { alpha[s] = -.infinity }
    alpha[0] = lp[t0, blank]
    if stateCount > 1 { alpha[1] = lp[t0, ext(1)] }
    if window.count > 1 {
      for t in (t0 + 1)...window.upperBound {
        for s in 0..<stateCount {
          let a0 = alpha[s]
          let a1 = s >= 1 ? alpha[s - 1] : -.infinity
          let canSkip = s >= 2 && s % 2 == 1 && seq[s / 2] != seq[s / 2 - 1]
          let a2 = canSkip ? alpha[s - 2] : -.infinity
          var m = max(max(a0, a1), a2)
          if !m.isFinite { m = 0 }
          next[s] = log(exp(a0 - m) + exp(a1 - m) + exp(a2 - m)) + m + lp[t, ext(s)]
        }
        swap(&alpha, &next)
      }
    }
    return logAddExp(alpha[stateCount - 1], stateCount > 1 ? alpha[stateCount - 2] : -.infinity)
  }

  // MARK: GOP (margin_gop, sf_gop, side_gops)

  /// Per token: peak over its region of logp(token) − max logp(any other non-blank token).
  static func marginGOP(
    _ lp: LogPosteriors, seq: [Int], regions: [ClosedRange<Int>], blank: Int
  ) -> [Double] {
    zip(seq, regions).map { token, region in
      var best = -Double.infinity
      for t in region {
        var other = -Double.infinity
        for c in 0..<lp.columns where c != token && c != blank { other = max(other, lp[t, c]) }
        if lp.columns <= 2 { other = neg }  // every other column masked, as numpy does
        best = max(best, lp[t, token] - other)
      }
      return best
    }
  }

  /// GOP-SF per token over its word's window: log P(canon) − log Σ P(canon, k→q, delete k,
  /// insert q after k), clipped to [GOP_FLOOR, 0]. Words run in parallel; results do not depend
  /// on scheduling (FR-16).
  static func sfGOP(
    _ lp: LogPosteriors, seq: [Int], wordOf: [Int], windows: [Int: ClosedRange<Int>], blank: Int
  ) -> [Double] {
    let words = Set(wordOf).sorted()
    var perWord = [[Double]](repeating: [], count: words.count)
    perWord.withUnsafeMutableBufferPointer { out in
      nonisolated(unsafe) let out = out
      DispatchQueue.concurrentPerform(iterations: words.count) { i in
        let w = words[i]
        let canon = wordOf.indices.filter { wordOf[$0] == w }.map { seq[$0] }
        out[i] = wordSF(lp, canon: canon, window: windows[w]!, blank: blank)
      }
    }
    var gops = [Double](repeating: 0, count: seq.count)
    for (i, w) in words.enumerated() {
      for (k, index) in wordOf.indices.filter({ wordOf[$0] == w }).enumerated() {
        gops[index] = perWord[i][k]
      }
    }
    return gops
  }

  /// GOP-SF of each sound of one word (`sf_gop` inner loop).
  static func wordSF(
    _ lp: LogPosteriors, canon: [Int], window: ClosedRange<Int>, blank: Int
  ) -> [Double] {
    var alpha: [Double] = []
    var next: [Double] = []
    var peak = [Double](repeating: -.infinity, count: lp.columns)
    for t in window { for c in 0..<lp.columns { peak[c] = max(peak[c], lp[t, c]) } }
    peak[blank] = neg
    // argsort(-peak, stable)[:MAX_CAND], then peak > CAND_LP
    let order = (0..<lp.columns).sorted { a, b in peak[a] != peak[b] ? peak[a] > peak[b] : a < b }
    let candidates = order.prefix(maxCandidates).filter { peak[$0] > candidateLogProb }
    let ll0 = ctcLogLikelihood(
      lp, window: window, seq: canon, blank: blank, alpha: &alpha, next: &next)
    return canon.indices.map { k in
      var total = ll0
      func add(_ s: [Int]) {
        total = logAddExp(
          total,
          ctcLogLikelihood(lp, window: window, seq: s, blank: blank, alpha: &alpha, next: &next))
      }
      for q in candidates {
        if q != canon[k] {
          var s = canon
          s[k] = q
          add(s)
        }
        var s = canon
        s.insert(q, at: k + 1)
        add(s)
      }
      var s = canon
      s.remove(at: k)
      add(s)
      let g = ll0.isFinite ? ll0 - total : gopFloor
      return max(gopFloor, min(0, g))
    }
  }

  /// (GOP-SF, margin, spans) per expected sound, or nil when the sounds cannot be aligned.
  static func sideGOPs(_ lp: LogPosteriors, seq: [Int], wordOf: [Int], blank: Int)
    -> (sf: [Double], margin: [Double], spans: [ClosedRange<Int>])?
  {
    guard let spans = viterbiAlign(lp, seq: seq, blank: blank) else { return nil }
    let regs = regions(spans, frames: lp.rows)
    var windows: [Int: ClosedRange<Int>] = [:]
    for (k, w) in wordOf.enumerated() {
      if let r = windows[w] {
        windows[w] = min(r.lowerBound, regs[k].lowerBound)...max(r.upperBound, regs[k].upperBound)
      } else {
        windows[w] = regs[k]
      }
    }
    return (
      sfGOP(lp, seq: seq, wordOf: wordOf, windows: windows, blank: blank),
      marginGOP(lp, seq: seq, regions: regs, blank: blank), spans
    )
  }

  // MARK: Reference analysis, word scores, flags

  /// Once per Reference and model. `logits`: raw `[T × V]` of the trimmed Reference audio.
  public static func analyzeReference(
    modelID: String, logits: FrameMatrix, offsetSeconds: Double, vocabulary v: PhoneVocabulary,
    words: [SoundWord]
  ) -> ModelReferenceAnalysis {
    let lp = foldedLogPosteriors(logits, vocabulary: v)
    let (tokens, frames) = greedy(lp, blank: v.blank)
    let wordOf = assignWords(frames: frames, words: words, offset: offsetSeconds)
    let keep = wordOf.indices.filter { wordOf[$0] != nil }
    let seq = keep.map { tokens[$0] }
    let phoneWords = keep.map { wordOf[$0]! }
    let g = seq.isEmpty ? nil : sideGOPs(lp, seq: seq, wordOf: phoneWords, blank: v.blank)
    return ModelReferenceAnalysis(
      modelID: modelID, offsetSeconds: offsetSeconds, frames: lp.rows, phoneIDs: seq,
      phones: seq.map { v.tokens[$0] }, phoneWords: phoneWords,
      phoneFrames: keep.map { frames[$0] }, gopSF: g?.sf, margin: g?.margin,
      spans: g?.spans.map { [$0.lowerBound, $0.upperBound] })
  }

  /// Per Reference word score for one model (nil: no sound in the word, or not alignable), and
  /// the take spans of the Reference's sounds.
  public static func modelWordScores(
    reference r: ModelReferenceAnalysis, wordCount n: Int, takeLogits: FrameMatrix,
    vocabulary v: PhoneVocabulary, configuration cfg: SoundComparisonConfiguration
  ) -> (scores: [Double?], spans: [ClosedRange<Int>]?) {
    let none = [Double?](repeating: nil, count: n)
    guard let refSF = r.gopSF, let refMargin = r.margin else { return (none, nil) }
    let lp = foldedLogPosteriors(takeLogits, vocabulary: v)
    guard let g = sideGOPs(lp, seq: r.phoneIDs, wordOf: r.phoneWords, blank: v.blank) else {
      return (none, nil)
    }
    let dsf = zip(refSF, g.sf).map { $0 - $1 }
    let dmg = zip(refMargin, g.margin).map { $0 - $1 }
    let scores = (0..<n).map { w -> Double? in
      let k = r.phoneWords.indices.filter { r.phoneWords[$0] == w }
      guard !k.isEmpty else { return nil }
      return aggregate(k.map { dsf[$0] }, cfg) + cfg.marginWeight * aggregate(k.map { dmg[$0] }, cfg)
    }
    return (scores, g.spans)
  }

  /// `_agg`: "min" = largest drop; "mix" = a·largest + (1−a)·mean of the two largest.
  static func aggregate(_ v: [Double], _ cfg: SoundComparisonConfiguration) -> Double {
    let s = v.sorted(by: >)
    let bottom2 = s.count >= 2 ? (s[0] + s[1]) / 2 : s[0]
    switch cfg.aggregation {
    case .min: return s[0]
    case .bottom2: return bottom2
    case .mix: return cfg.mixA * s[0] + (1 - cfg.mixA) * bottom2
    }
  }

  /// Mean over models; nil if any model has no score for the word.
  public static func fuse(_ columns: [[Double?]]) -> [Double?] {
    guard let n = columns.first?.count else { return [] }
    return (0..<n).map { i in
      var sum = 0.0
      for column in columns {
        guard let x = column[i] else { return nil }
        sum += x
      }
      return sum / Double(columns.count)
    }
  }

  static func letterCount(_ word: String) -> Int {
    word.unicodeScalars.filter { ("A"..."Z").contains($0) || ("a"..."z").contains($0) }.count
  }

  /// FR-9 eligibility: scored, timed, ≥ minLetters ASCII letters, Reference span ≥ minDuration.
  public static func isEligible(
    _ w: SoundWord, score: Double?, _ cfg: SoundComparisonConfiguration
  ) -> Bool {
    guard score != nil, let s = w.start, let e = w.end else { return false }
    return letterCount(w.text) >= cfg.minLetters && (e - s) >= cfg.minDurationSeconds
  }

  /// Flagged Reference word indices, strongest first (FR-7 threshold, FR-8 cap, FR-9).
  public static func flags(
    scores: [Double?], words: [SoundWord], _ cfg: SoundComparisonConfiguration
  ) -> [Int] {
    let eligible = words.indices.filter { isEligible(words[$0], score: scores[$0], cfg) }
      .sorted { a, b in scores[a]! != scores[b]! ? scores[a]! > scores[b]! : a < b }
    return eligible.prefix(cfg.maxFlags).filter { scores[$0]! > cfg.threshold }
  }

  public static func wordScores(
    fused: [Double?], words: [SoundWord], _ cfg: SoundComparisonConfiguration
  ) -> [WordSoundScore] {
    let flagged = flags(scores: fused, words: words, cfg)
    return words.indices.map { i in
      let rank = flagged.firstIndex(of: i).map { $0 + 1 }
      return WordSoundScore(
        wordIndex: i, text: words[i].text, score: fused[i],
        eligible: isEligible(words[i], score: fused[i], cfg), flagged: rank != nil,
        flagRank: rank)
    }
  }
}
