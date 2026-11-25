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

/// RPS (eng_r3): which sounds may replace each expected sound in the GOP-SF denominator.
/// `<model>-substitutions.json`: `{"vocab": [...], "allowed": {"p": [q, ...]}}`; a sound with no
/// entry has no substitutes.
public struct SubstitutionTable: Sendable, Equatable {
  public let size: Int
  private let allowed: [Bool]

  public init(size: Int, allowed: [Int: [Int]]) {
    self.size = size
    var table = [Bool](repeating: false, count: size * size)
    for (p, qs) in allowed where p >= 0 && p < size {
      for q in qs where q >= 0 && q < size { table[p * size + q] = true }
    }
    self.allowed = table
  }

  /// Fails unless the table was made for exactly `vocabulary`'s tokens.
  public init(contentsOf url: URL, vocabulary: PhoneVocabulary) throws {
    struct File: Decodable {
      let vocab: [String]
      let allowed: [String: [Int]]
    }
    let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    guard file.vocab == vocabulary.tokens else {
      throw SoundComparisonError.substitutionTableMismatch(url.lastPathComponent)
    }
    var allowed: [Int: [Int]] = [:]
    for (key, value) in file.allowed {
      guard let p = Int(key) else { continue }
      allowed[p] = value
    }
    self.init(size: file.vocab.count, allowed: allowed)
  }

  @inline(__always) public func allows(_ canonical: Int, _ substitute: Int) -> Bool {
    canonical < size && substitute < size && allowed[canonical * size + substitute]
  }
}

/// A phone model that turns 16 kHz speech into raw CTC logits at 20 ms per frame.
public protocol PhoneLogitModel {
  var modelID: String { get }
  var vocabulary: PhoneVocabulary { get }
  func rawLogits(samples: [Float]) throws -> FrameMatrix
  /// Logits and, when the model has one, its encoder output on the same frames (ZIPA `hidden`).
  func rawOutputs(samples: [Float]) throws -> (logits: FrameMatrix, hidden: FrameMatrix?)
}

extension PhoneLogitModel {
  public func rawOutputs(samples: [Float]) throws -> (logits: FrameMatrix, hidden: FrameMatrix?) {
    (try rawLogits(samples: samples), nil)
  }
}

/// `lite_r3` / `full_r3`: trim silence, run each phone model on the speech only, score with
/// `SoundComparisonScoring`, then the speaker-relative shift and the ZIPA-encoder word DTW
/// (`SoundWordDTW`). Platform-free: Core ML runners live in `PhoneModelRunners.swift`.
public final class PhoneModelSoundComparisonEngine: SoundComparisonEngine {
  public let configuration: SoundComparisonConfiguration
  public let models: [any PhoneLogitModel]
  /// One per model when the configuration restricts substitutions, else empty.
  public let substitutions: [SubstitutionTable?]
  public var id: String { configuration.id }
  public var version: String { SoundComparisonConfiguration.engineVersion }

  public init(
    configuration: SoundComparisonConfiguration, models: [any PhoneLogitModel],
    substitutions: [SubstitutionTable?] = []
  ) throws {
    guard models.map(\.modelID) == configuration.models else {
      throw SoundComparisonError.unexpectedModel(models.map(\.modelID).joined(separator: ","))
    }
    if configuration.restrictedSubstitutions {
      guard substitutions.count == models.count,
        zip(substitutions, models).allSatisfy({ $0?.size == $1.vocabulary.tokens.count })
      else { throw SoundComparisonError.engineNotInstalled(configuration.id) }
    }
    self.configuration = configuration
    self.models = models
    self.substitutions = configuration.restrictedSubstitutions ? substitutions : []
  }

  private func table(_ index: Int) -> SubstitutionTable? {
    substitutions.indices.contains(index) ? substitutions[index] : nil
  }

  /// The word DTW reads the first model's encoder output (ZIPA in both engines).
  private var usesDTW: Bool { configuration.dtwWeight != 0 }

  public func analyzeReference(samples: [Float], words: [SoundWord]) throws -> ReferenceAnalysis {
    let (speech, offset) = SpeechTrim.trim(samples)
    var hidden: FrameMatrix?
    var analyses: [ModelReferenceAnalysis] = []
    for (index, model) in models.enumerated() {
      let output = try model.rawOutputs(samples: speech)
      if index == 0 { hidden = output.hidden }
      analyses.append(
        SoundComparisonScoring.analyzeReference(
          modelID: model.modelID, logits: output.logits, offsetSeconds: offset,
          vocabulary: model.vocabulary, words: words, substitutions: table(index)))
    }
    let frames =
      usesDTW
      ? hidden.map { SoundWordDTW.referenceFrames(hidden: $0, offsetSeconds: offset, words: words) }
      : nil
    return ReferenceAnalysis(
      engineID: id, engineVersion: version, words: words, models: analyses, wordFrames: frames)
  }

  public func compare(reference: ReferenceAnalysis, takeSamples: [Float], takeWords: [SoundWord?])
    throws -> SoundComparisonResult
  {
    guard reference.engineID == id, reference.engineVersion == version,
      reference.models.map(\.modelID) == configuration.models
    else { throw SoundComparisonError.referenceFromOtherEngine }
    let (speech, offset) = SpeechTrim.trim(takeSamples)
    var columns: [[Double?]] = []
    var phones: [SoundPhone] = []
    var hidden: FrameMatrix?
    for (index, (model, analysis)) in zip(models, reference.models).enumerated() {
      let output = try model.rawOutputs(samples: speech)
      if index == 0 { hidden = output.hidden }
      let scored = SoundComparisonScoring.modelWordScores(
        reference: analysis, wordCount: reference.words.count, takeLogits: output.logits,
        vocabulary: model.vocabulary, configuration: configuration, substitutions: table(index))
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
    var costs = [Double?](repeating: nil, count: reference.words.count)
    if usesDTW, let frames = reference.wordFrames, let hidden,
      takeWords.count == reference.words.count
    {
      costs = SoundWordDTW.costs(
        reference: frames, takeHidden: hidden, takeOffsetSeconds: offset, takeWords: takeWords)
    }
    let fused = SoundComparisonScoring.secondKey(
      SoundComparisonScoring.relativeShift(SoundComparisonScoring.fuse(columns), configuration),
      dtwCosts: costs, configuration)
    return SoundComparisonResult(
      engineID: id, engineVersion: version,
      words: SoundComparisonScoring.wordScores(fused: fused, words: reference.words, configuration),
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
    _ lp: LogPosteriors, seq: [Int], wordOf: [Int], windows: [Int: ClosedRange<Int>], blank: Int,
    substitutions: SubstitutionTable? = nil
  ) -> [Double] {
    let words = Set(wordOf).sorted()
    var perWord = [[Double]](repeating: [], count: words.count)
    perWord.withUnsafeMutableBufferPointer { out in
      nonisolated(unsafe) let out = out
      DispatchQueue.concurrentPerform(iterations: words.count) { i in
        let w = words[i]
        let canon = wordOf.indices.filter { wordOf[$0] == w }.map { seq[$0] }
        out[i] = wordSF(
          lp, canon: canon, window: windows[w]!, blank: blank, substitutions: substitutions)
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

  /// GOP-SF of each sound of one word (`sf_gop` inner loop; `sf_gop_rps` with a table: a
  /// substitute q for sound k only when the table allows it, insertions and deletion as before).
  static func wordSF(
    _ lp: LogPosteriors, canon: [Int], window: ClosedRange<Int>, blank: Int,
    substitutions: SubstitutionTable? = nil
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
        if q != canon[k], substitutions?.allows(canon[k], q) ?? true {
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
  static func sideGOPs(
    _ lp: LogPosteriors, seq: [Int], wordOf: [Int], blank: Int,
    substitutions: SubstitutionTable? = nil
  ) -> (sf: [Double], margin: [Double], spans: [ClosedRange<Int>])? {
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
      sfGOP(
        lp, seq: seq, wordOf: wordOf, windows: windows, blank: blank,
        substitutions: substitutions),
      marginGOP(lp, seq: seq, regions: regs, blank: blank), spans
    )
  }

  // MARK: Reference analysis, word scores, flags

  /// Once per Reference and model. `logits`: raw `[T × V]` of the trimmed Reference audio.
  public static func analyzeReference(
    modelID: String, logits: FrameMatrix, offsetSeconds: Double, vocabulary v: PhoneVocabulary,
    words: [SoundWord], substitutions: SubstitutionTable? = nil
  ) -> ModelReferenceAnalysis {
    let lp = foldedLogPosteriors(logits, vocabulary: v)
    let (tokens, frames) = greedy(lp, blank: v.blank)
    let wordOf = assignWords(frames: frames, words: words, offset: offsetSeconds)
    let keep = wordOf.indices.filter { wordOf[$0] != nil }
    let seq = keep.map { tokens[$0] }
    let phoneWords = keep.map { wordOf[$0]! }
    let g =
      seq.isEmpty
      ? nil
      : sideGOPs(lp, seq: seq, wordOf: phoneWords, blank: v.blank, substitutions: substitutions)
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
    vocabulary v: PhoneVocabulary, configuration cfg: SoundComparisonConfiguration,
    substitutions: SubstitutionTable? = nil
  ) -> (scores: [Double?], spans: [ClosedRange<Int>]?) {
    let none = [Double?](repeating: nil, count: n)
    guard let refSF = r.gopSF, let refMargin = r.margin else { return (none, nil) }
    let lp = foldedLogPosteriors(takeLogits, vocabulary: v)
    guard
      let g = sideGOPs(
        lp, seq: r.phoneIDs, wordOf: r.phoneWords, blank: v.blank, substitutions: substitutions)
    else {
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

  /// numpy `median` (mean of the two middle values for an even count).
  static func median(_ values: [Double]) -> Double {
    let s = values.sorted()
    let m = s.count / 2
    return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
  }

  /// Speaker-relative shift: every score − `relativeShift` × median of the take's scored words
  /// (eligible or not).
  public static func relativeShift(_ scores: [Double?], _ cfg: SoundComparisonConfiguration)
    -> [Double?]
  {
    let scored = scores.compactMap { $0 }
    guard cfg.relativeShift != 0, !scored.isEmpty else { return scores }
    let shift = cfg.relativeShift * median(scored)
    return scores.map { $0.map { $0 - shift } }
  }

  /// Second key: + `dtwWeight` × (DTW cost − `dtwCenter`). A word with no cost keeps its score.
  public static func secondKey(
    _ scores: [Double?], dtwCosts: [Double?], _ cfg: SoundComparisonConfiguration
  ) -> [Double?] {
    zip(scores, dtwCosts).map { score, cost in
      guard let score, let cost else { return score }
      return score + cfg.dtwWeight * (cost - cfg.dtwCenter)
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

/// eng_r3 second key: per word, DTW between the Reference's and the take's ZIPA encoder frames.
/// Each clip's frames are standardised over its trimmed audio and L2-normalised; the cost of a
/// cell is the cosine distance clipped to [0, 2]; steps (1,1), (1,0), (0,1) with unit weights
/// (ties: diagonal, vertical, horizontal); the word's cost is the mean cost on the path, divided
/// by median(raw costs of the take's words)^0.5.
public enum SoundWordDTW {
  static let beta = 0.5

  /// `_prep`: per-column standardisation (population std + 1e-5), then row L2 norm (+ 1e-8).
  static func prepared(_ h: FrameMatrix) -> FrameMatrix {
    let rows = h.rows
    let columns = h.columns
    guard rows > 0 else { return h }
    var x = h.values.map { $0.isFinite ? Double($0) : 0 }
    for c in 0..<columns {
      var mean = 0.0
      for r in 0..<rows { mean += x[r * columns + c] }
      mean /= Double(rows)
      var variance = 0.0
      for r in 0..<rows {
        let d = x[r * columns + c] - mean
        variance += d * d
      }
      let scale = 1 / ((variance / Double(rows)).squareRoot() + 1e-5)
      for r in 0..<rows { x[r * columns + c] = (x[r * columns + c] - mean) * scale }
    }
    var out = [Float](repeating: 0, count: x.count)
    for r in 0..<rows {
      var norm = 0.0
      for c in 0..<columns { norm += x[r * columns + c] * x[r * columns + c] }
      let inverse = 1 / (norm.squareRoot() + 1e-8)
      for c in 0..<columns { out[r * columns + c] = Float(x[r * columns + c] * inverse) }
    }
    return FrameMatrix(rows: rows, columns: columns, values: out)
  }

  /// `_span`: frames [floor((start − offset)/hop), ceil((end − offset)/hop)) clipped to the clip;
  /// nil under 2 frames or untimed.
  static func span(_ word: SoundWord?, offsetSeconds: Double, frames: Int) -> Range<Int>? {
    guard let word, let start = word.start, let end = word.end else { return nil }
    let hop = SoundComparisonScoring.hopSeconds
    let s = max(0, Int(((start - offsetSeconds) / hop).rounded(.down)))
    let e = min(frames, Int(((end - offsetSeconds) / hop).rounded(.up)))
    return e - s >= 2 ? s..<e : nil
  }

  /// The prepared Reference frames of each word span, as stored in `ReferenceAnalysis`.
  public static func referenceFrames(hidden: FrameMatrix, offsetSeconds: Double, words: [SoundWord])
    -> ReferenceWordFrames
  {
    let prepared = prepared(hidden)
    var counts: [Int] = []
    var bits: [UInt16] = []
    for word in words {
      guard let span = span(word, offsetSeconds: offsetSeconds, frames: prepared.rows) else {
        counts.append(0)
        continue
      }
      counts.append(span.count)
      for r in span { bits += prepared.row(r).map { Half.bits($0).littleEndian } }
    }
    let data = bits.withUnsafeBufferPointer { Data(buffer: $0) }
    return ReferenceWordFrames(dimension: hidden.columns, frameCounts: counts, values: data)
  }

  /// Calibrated DTW cost per Reference word (nil: no span on either side).
  public static func costs(
    reference: ReferenceWordFrames, takeHidden: FrameMatrix, takeOffsetSeconds: Double,
    takeWords: [SoundWord?]
  ) -> [Double?] {
    let d = reference.dimension
    guard takeHidden.columns == d, reference.frameCounts.count == takeWords.count,
      reference.values.count == 2 * d * reference.frameCounts.reduce(0, +)
    else { return [Double?](repeating: nil, count: takeWords.count) }
    let stored: [Float] = reference.values.withUnsafeBytes { raw in
      raw.bindMemory(to: UInt16.self).map { Half.float(UInt16(littleEndian: $0)) }
    }
    let take = prepared(takeHidden)
    var raw: [Double?] = []
    var first = 0
    for (count, word) in zip(reference.frameCounts, takeWords) {
      defer { first += count }
      guard count > 0,
        let t = span(word, offsetSeconds: takeOffsetSeconds, frames: take.rows)
      else {
        raw.append(nil)
        continue
      }
      var cost = [Double](repeating: 0, count: count * t.count)
      for i in 0..<count {
        let r = (first + i) * d
        for (j, row) in t.enumerated() {
          var dot: Float = 0
          let base = row * d
          for c in 0..<d { dot += stored[r + c] * take.values[base + c] }
          cost[i * t.count + j] = min(max(1 - Double(dot), 0), 2)
        }
      }
      raw.append(dtw(cost, rows: count, columns: t.count))
    }
    let values = raw.compactMap { $0 }
    let median = values.isEmpty ? 1 : max(SoundComparisonScoring.median(values), 1e-8)
    let scale = pow(median, beta)
    return raw.map { $0.map { $0 / scale } }
  }

  /// `_dtw`: mean cell cost along the best path.
  static func dtw(_ cost: [Double], rows n: Int, columns m: Int) -> Double {
    var total = [Double](repeating: .infinity, count: (n + 1) * (m + 1))
    var length = [Double](repeating: 0, count: (n + 1) * (m + 1))
    total[0] = 0
    let w = m + 1
    for i in 1...n {
      for j in 1...m {
        let a = total[(i - 1) * w + j - 1]
        let b = total[(i - 1) * w + j]
        let c = total[i * w + j - 1]
        let cell = cost[(i - 1) * m + j - 1]
        if a <= b && a <= c {
          total[i * w + j] = a + cell
          length[i * w + j] = length[(i - 1) * w + j - 1] + 1
        } else if b <= c {
          total[i * w + j] = b + cell
          length[i * w + j] = length[(i - 1) * w + j] + 1
        } else {
          total[i * w + j] = c + cell
          length[i * w + j] = length[i * w + j - 1] + 1
        }
      }
    }
    return total[n * w + m] / length[n * w + m]
  }
}

/// IEEE 754 half precision, written out (Float16 is not available on every Core platform).
enum Half {
  /// Round to nearest, ties to even.
  static func bits(_ value: Float) -> UInt16 {
    let x = value.bitPattern
    let sign = UInt16((x >> 16) & 0x8000)
    let magnitude = x & 0x7FFF_FFFF
    if magnitude > 0x7F80_0000 { return sign | 0x7E00 }  // NaN
    let exponent = Int(magnitude >> 23) - 127 + 15
    if exponent >= 31 { return sign | 0x7C00 }
    var mantissa = magnitude & 0x7F_FFFF
    if exponent <= 0 {
      if exponent < -10 { return sign }
      mantissa |= 0x80_0000
      let shift = UInt32(14 - exponent)
      var h = mantissa >> shift
      let rest = mantissa & ((1 << shift) - 1)
      let half = UInt32(1) << (shift - 1)
      if rest > half || (rest == half && h & 1 == 1) { h += 1 }
      return sign | UInt16(h)
    }
    var h = UInt32(exponent) << 10 | (mantissa >> 13)
    let rest = mantissa & 0x1FFF
    if rest > 0x1000 || (rest == 0x1000 && h & 1 == 1) { h += 1 }
    return sign | UInt16(h)
  }

  static func float(_ h: UInt16) -> Float {
    let negative = h & 0x8000 != 0
    let exponent = Int((h >> 10) & 0x1F)
    let mantissa = UInt32(h & 0x3FF)
    let value: Float
    switch exponent {
    case 0: value = Float(mantissa) * 0x1p-24
    case 31: value = mantissa == 0 ? .infinity : .nan
    default: value = Float(bitPattern: UInt32(exponent - 15 + 127) << 23 | mantissa << 13)
    }
    return negative ? -value : value
  }
}
