import Foundation
import Testing

@testable import VoiceCoachCore

/// Returns fixed logits, whatever the audio: lets the real scoring run without Core ML.
private final class FixedLogits: PhoneLogitModel {
  let modelID = "zipa"
  let vocabulary = PhoneVocabulary(tokens: ["<blk>", "k", "a", "t", "s", "i", "z", "<unk>"], blank: 0)
  var queue: [FrameMatrix]

  init(_ queue: [FrameMatrix]) { self.queue = queue }

  func rawLogits(samples: [Float]) throws -> FrameMatrix { queue.removeFirst() }
}

/// 20 ms frames: each segment is (token, frames); the token gets logit 10, the rest 0.
private func logits(_ segments: [(Int, Int)]) -> FrameMatrix {
  let frames = segments.flatMap { Array(repeating: $0.0, count: $0.1) }
  var matrix = FrameMatrix(rows: frames.count, columns: 8)
  for (t, token) in frames.enumerated() { matrix[t, token] = 10 }
  return matrix
}

/// "cat" (0–0.5 s) then "sit" (0.6–1.1 s); `s` is the first sound of "sit".
private func utterance(s: Int) -> FrameMatrix {
  logits([(0, 5), (1, 6), (0, 1), (2, 6), (0, 1), (3, 6), (0, 6), (s, 6), (0, 1), (5, 6), (0, 1), (3, 6), (0, 9)])
}

private let words = [
  SoundWord(text: "cat", start: 0.0, end: 0.5), SoundWord(text: "sit", start: 0.6, end: 1.1),
]
private let tone = (0..<19_200).map { Float(sin(Double($0) * 0.05) * 0.3) }

@Suite("Sound comparison")
struct SoundComparisonTests {
  @Test("A swapped sound is flagged on its word, and the same input gives the same flags")
  func fixedInputFlags() throws {
    let model = FixedLogits([utterance(s: 4), utterance(s: 6), utterance(s: 6)])
    let engine = try PhoneModelSoundComparisonEngine(configuration: .lite, models: [model])

    let reference = try engine.analyzeReference(samples: tone, words: words)
    #expect(reference.models[0].phones == ["k", "a", "t", "s", "i", "t"])
    #expect(reference.models[0].phoneWords == [0, 0, 0, 1, 1, 1])
    let first = try engine.compare(reference: reference, takeSamples: tone, takeWords: words)
    let second = try engine.compare(reference: reference, takeSamples: tone, takeWords: words)

    #expect(first.flags.map(\.text) == ["sit"])
    #expect(first.flags.first?.flagRank == 1)
    #expect(first.words[0].flagged == false)
    #expect(first.phones.map(\.symbol) == ["k", "a", "t", "s", "i", "t"])
    #expect(first == second)  // FR-16
  }

  @Test("At most three flags, strongest first, never on short words")
  func flagCapAndEligibility() {
    let words = ["is", "think", "world", "asked", "ship", "a"].enumerated().map {
      SoundWord(text: $0.element, start: Double($0.offset), end: Double($0.offset) + 0.4)
    }
    let scores: [Double?] = [99, 20, 30, 40, 25, 99]
    let flags = SoundComparisonScoring.flags(scores: scores, words: words, .lite)
    #expect(flags == [3, 2, 4])  // "is" and "a" are too short (FR-9), "think" is fourth (FR-8)
    let short = SoundWord(text: "ship", start: 0, end: 0.1)
    #expect(!SoundComparisonScoring.isEligible(short, score: 50, .lite))
  }

  @Test("Takes that fail today's quality rules are not compared")
  func skipReasons() {
    let reference = CoreTestFixtures.session()
    #expect(
      SoundComparisonSkipReason.check(
        reference: reference, attempt: CoreTestFixtures.session(), localeIdentifier: "en-US")
        == nil)
    #expect(
      SoundComparisonSkipReason.check(
        reference: nil, attempt: CoreTestFixtures.session(), localeIdentifier: nil) == .noReference)
    #expect(
      SoundComparisonSkipReason.check(
        reference: reference, attempt: CoreTestFixtures.session(snrDB: 4), localeIdentifier: nil)
        == .noisy)
    #expect(
      SoundComparisonSkipReason.check(
        reference: reference, attempt: CoreTestFixtures.session(words: ["a", "b", "c", "d"]),
        localeIdentifier: nil) == .wordsDidNotLineUp)
    #expect(
      SoundComparisonSkipReason.check(
        reference: reference, attempt: CoreTestFixtures.session(), localeIdentifier: "fr-FR")
        == .notEnglish)
  }

  @Test("Results are kept per engine and compared only within one engine version")
  func perEngineResults() throws {
    let lite = SoundComparisonResult(engineID: "lite", engineVersion: "v1", words: [], phones: [])
    var full = lite
    full.engineID = "full"
    var older = lite
    older.engineVersion = "v0"
    #expect(!lite.isComparable(with: full))  // FR-21
    #expect(!lite.isComparable(with: older))
    #expect(lite.isComparable(with: lite))

    let sounds = TakeSounds(comparisons: ["lite": lite, "full": full])
    let decoded = try JSONDecoder().decode(TakeSounds.self, from: JSONEncoder().encode(sounds))
    #expect(decoded == sounds)
    #expect(decoded.comparison(engineID: "lite", engineVersion: "v0") == nil)
    #expect(sounds.removingEngine("lite").comparisons.keys.sorted() == ["full"])
  }

  @Test("A Reference analysis keeps its word frames, and older ones without them still decode")
  func referenceAnalysisStorage() throws {
    let frames = ReferenceWordFrames(dimension: 2, frameCounts: [1, 0], values: Data([0, 60, 0, 188]))
    let analysis = ReferenceAnalysis(
      engineID: "lite", engineVersion: "eng_r3", words: words, models: [], wordFrames: frames)
    let sounds = TakeSounds(referenceAnalyses: ["lite": analysis])
    let data = try JSONEncoder().encode(sounds)
    #expect(try JSONDecoder().decode(TakeSounds.self, from: data) == sounds)
    #expect(String(decoding: data, as: UTF8.self).contains("\"values\":\"ADwAvA==\""))

    let older = Data(
      #"{"referenceAnalyses":{"lite":{"engineID":"lite","engineVersion":"eng_final-r2.1","words":[],"models":[]}}}"#
        .utf8)
    let decoded = try JSONDecoder().decode(TakeSounds.self, from: older)
    #expect(decoded.referenceAnalyses["lite"]?.wordFrames == nil)
    #expect(
      decoded.referenceAnalysis(
        engineID: "lite", engineVersion: SoundComparisonConfiguration.engineVersion, words: [])
        == nil)
  }

  @Test("Restricted substitutions: only listed sounds compete, and full needs a table per model")
  func substitutionTable() throws {
    let table = SubstitutionTable(size: 4, allowed: [1: [2], 3: [9]])
    #expect(table.allows(1, 2))
    #expect(!table.allows(2, 1))
    #expect(!table.allows(3, 9))
    let model = FixedLogits([])
    #expect(throws: SoundComparisonError.self) {
      _ = try PhoneModelSoundComparisonEngine(configuration: .lite.restricted, models: [model])
    }
    let tables = [SubstitutionTable(size: model.vocabulary.tokens.count, allowed: [:])]
    _ = try PhoneModelSoundComparisonEngine(
      configuration: .lite.restricted, models: [model], substitutions: tables)

    // "sit" where "s" sounds as much like "z": "z" only competes when the table allows it.
    var take = utterance(s: 4)
    for t in 31...36 { take[t, 6] = 10 }
    let lp = SoundComparisonScoring.foldedLogPosteriors(take, vocabulary: model.vocabulary)
    let open = SoundComparisonScoring.wordSF(lp, canon: [4, 5, 3], window: 30...51, blank: 0)
    let none = SoundComparisonScoring.wordSF(
      lp, canon: [4, 5, 3], window: 30...51, blank: 0, substitutions: tables[0])
    #expect(open[0] < none[0])
  }

  @Test("Speaker-relative shift and the DTW second key follow the lab's order")
  func shiftAndSecondKey() {
    let full = SoundComparisonConfiguration.full
    let shifted = SoundComparisonScoring.relativeShift([1, nil, 3, 5, 7], full)
    let shift = 0.2 * 4.0  // 0.2 × median 4
    let expected: [Double?] = [1 - shift, nil, 3 - shift, 5 - shift, 7 - shift]
    #expect(shifted == expected)
    #expect(SoundComparisonScoring.relativeShift([1, 3], .lite) == [1, 3])
    let lite = SoundComparisonScoring.secondKey([10, 10, nil], dtwCosts: [1, nil, 1], .lite)
    let keyed: Double = 10 + 24 * (1 - 0.74)
    #expect(abs(lite[0]! - keyed) < 1e-12)
    #expect(lite[1] == 10 && lite[2] == nil)
  }

  @Test("Word DTW: same frames cost nothing, other frames cost more, half floats round-trip")
  func wordDTW() {
    var values = [Float](repeating: 0, count: 6 * 4)
    for r in 0..<6 { values[r * 4 + r % 4] = 1 + Float(r) }
    let hidden = FrameMatrix(rows: 6, columns: 4, values: values)
    let words = [
      SoundWord(text: "one", start: 0, end: 0.06), SoundWord(text: "two", start: 0.06, end: 0.12),
      SoundWord(text: "x", start: nil, end: nil),
    ]
    let frames = SoundWordDTW.referenceFrames(hidden: hidden, offsetSeconds: 0, words: words)
    #expect(frames.frameCounts == [3, 3, 0])
    #expect(frames.values.count == 2 * 4 * 6)
    let same = SoundWordDTW.costs(
      reference: frames, takeHidden: hidden, takeOffsetSeconds: 0, takeWords: words)
    #expect(same[2] == nil)
    #expect(same.compactMap { $0 }.allSatisfy { $0 < 0.05 })
    let swapped = SoundWordDTW.costs(
      reference: frames, takeHidden: hidden, takeOffsetSeconds: 0, takeWords: [words[1], words[0], nil])
    #expect(swapped[0]! > 0.1)

    #expect(SoundWordDTW.dtw([0, 1, 1, 0], rows: 2, columns: 2) == 0)
    #expect(SoundWordDTW.dtw([1, 2, 3], rows: 1, columns: 3) == 2)
    for x: Float in [0, 1, -1, 0.333_33, 1e-6, -2.5e-5, 65_504, 0.044] {
      #expect(abs(Half.float(Half.bits(x)) - x) <= max(abs(x) * 0x1p-11, 0x1p-24))
    }
  }

  @Test("Each Reference word gets the take word the transcripts matched, or a lone substitute")
  func takeWordMap() {
    let reference = CoreTestFixtures.session(words: ["she", "read", "a", "book"])
    let attempt = CoreTestFixtures.session(words: ["she", "red", "a", "book", "today"])
    let map = SoundComparisonWordMap.takeWords(reference: reference, attempt: attempt)
    #expect(map.map { $0?.text } == ["she", "red", "a", "book"])
    let edge = SoundComparisonWordMap.takeWords(
      reference: CoreTestFixtures.session(words: ["think", "so"]),
      attempt: CoreTestFixtures.session(words: ["sink", "so"]))
    #expect(edge.map { $0?.text } == ["sink", "so"])
  }
}

extension SoundComparisonConfiguration {
  fileprivate var restricted: SoundComparisonConfiguration {
    var copy = self
    copy.restrictedSubstitutions = true
    return copy
  }
}

// MARK: - Parity: the lab's round-3 golden set (build/pron-lab/proto/eng_r3/golden).

private let repoRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private enum LabPaths {
  static let root = repoRoot.appendingPathComponent("build/pron-lab")
}
private let lab = LabPaths.root
private let golden = lab.appendingPathComponent("proto/eng_r3/golden")
private let goldenFile = golden.appendingPathComponent("pairs.json")
/// Engine ids in the golden set.
private let labEngine = ["lite": "lite_r3", "full": "full_r3"]
private let engineRoot = FileManager.default.urls(
  for: .applicationSupportDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("VoiceCoach/SoundComparison")
private func installed(_ id: String) -> Bool {
  FileManager.default.fileExists(
    atPath: engineRoot.appendingPathComponent("\(id)/manifest.json").path)
    && FileManager.default.fileExists(atPath: goldenFile.path)
}

private struct GoldenPair {
  let id: String
  let refWAV: String
  let takeWAV: String
  let refWords: [SoundWord]
  let takeWords: [SoundWord?]
  let engines: [String: [String: Any]]

  func flags(_ engine: String) -> [Int] {
    (engines[engine]?["flags"] as? [NSNumber] ?? []).map(\.intValue)
  }

  func robust(_ engine: String) -> Bool { engines[engine]?["robust"] as? Bool ?? false }

  func scores(_ engine: String) -> [Double?] {
    (engines[engine]?["scores"] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue }
  }

  static func loadAll() throws -> [GoldenPair] {
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: goldenFile)) as? [String: Any])
    func words(_ value: Any?) -> [SoundWord] {
      (value as? [[String: Any]] ?? []).map {
        SoundWord(
          text: $0["word"] as? String ?? "", start: ($0["start"] as? NSNumber)?.doubleValue,
          end: ($0["end"] as? NSNumber)?.doubleValue)
      }
    }
    return (root["pairs"] as? [[String: Any]] ?? []).map { pair in
      GoldenPair(
        id: pair["id"] as? String ?? "", refWAV: pair["ref_wav"] as? String ?? "",
        takeWAV: pair["take_wav"] as? String ?? "", refWords: words(pair["ref_words"]),
        takeWords: words(pair["take_words"]).map { $0.start == nil ? nil : $0 },
        engines: pair["engines"] as? [String: [String: Any]] ?? [:])
    }
  }
}

/// A 2-D little-endian float32 `.npy` file.
private func loadNPY(_ url: URL) throws -> FrameMatrix {
  let data = try Data(contentsOf: url)
  let headerLength = Int(data[8]) | Int(data[9]) << 8
  let header = String(decoding: data[10..<(10 + headerLength)], as: UTF8.self)
  #expect(header.contains("'<f4'") && header.contains("False"))
  let shape = try #require(header.split(separator: "(").last?.split(separator: ")").first)
    .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
  let values = data[(10 + headerLength)...].withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
  return FrameMatrix(rows: shape[0], columns: shape[1], values: values)
}

@Suite("Sound comparison golden scoring")
struct SoundComparisonGoldenScoringTests {
  /// The lab's raw Core ML logits and ZIPA `hidden` for 3 pairs, scored without Core ML: checks
  /// the port of `final_engine_r3` itself (RPS, shift, DTW). Skipped without the golden set.
  @Test("Scoring the lab's logits gives the lab's word scores and flags", arguments: ["lite", "full"])
  func goldenLogits(engineID: String) throws {
    guard FileManager.default.fileExists(atPath: goldenFile.path) else { return }
    let cfg = try #require(SoundComparisonConfiguration.named(engineID))
    let blanks = ["zipa": 0, "hubert8": 40, "xlsr8": 0]
    var checked = 0
    var worst = 0.0
    for pair in try GoldenPair.loadAll() {
      let folder = golden.appendingPathComponent("logits/\(pair.id)")
      guard FileManager.default.fileExists(atPath: folder.path),
        let entry = pair.engines[labEngine[engineID]!],
        let perModel = entry["models"] as? [String: [String: Any]]
      else { continue }
      var columns: [[Double?]] = []
      for modelID in cfg.models {
        let table = try #require(
          JSONSerialization.jsonObject(
            with: Data(
              contentsOf: golden.appendingPathComponent("rps_allowed_\(modelID).json")))
            as? [String: Any])
        let vocabulary = PhoneVocabulary(
          tokens: table["vocab"] as? [String] ?? [], blank: blanks[modelID]!)
        let substitutions =
          cfg.restrictedSubstitutions
          ? try SubstitutionTable(
            contentsOf: golden.appendingPathComponent("rps_allowed_\(modelID).json"),
            vocabulary: vocabulary) : nil
        let info = try #require(perModel[modelID])
        let reference = SoundComparisonScoring.analyzeReference(
          modelID: modelID, logits: try loadNPY(folder.appendingPathComponent("\(modelID)_ref.npy")),
          offsetSeconds: (info["ref_offset_s"] as! NSNumber).doubleValue, vocabulary: vocabulary,
          words: pair.refWords, substitutions: substitutions)
        #expect(reference.phoneIDs == (info["expected_ids"] as? [NSNumber] ?? []).map(\.intValue))
        columns.append(
          SoundComparisonScoring.modelWordScores(
            reference: reference, wordCount: pair.refWords.count,
            takeLogits: try loadNPY(folder.appendingPathComponent("\(modelID)_take.npy")),
            vocabulary: vocabulary, configuration: cfg, substitutions: substitutions
          ).scores)
      }
      let zipa = try #require(perModel["zipa"])
      let frames = SoundWordDTW.referenceFrames(
        hidden: try loadNPY(folder.appendingPathComponent("zipa_hidden_ref.npy")),
        offsetSeconds: (zipa["ref_offset_s"] as! NSNumber).doubleValue, words: pair.refWords)
      let costs = SoundWordDTW.costs(
        reference: frames,
        takeHidden: try loadNPY(folder.appendingPathComponent("zipa_hidden_take.npy")),
        takeOffsetSeconds: (zipa["take_offset_s"] as! NSNumber).doubleValue,
        takeWords: pair.takeWords)
      let scores = SoundComparisonScoring.secondKey(
        SoundComparisonScoring.relativeShift(SoundComparisonScoring.fuse(columns), cfg),
        dtwCosts: costs, cfg)
      let expected = pair.scores(labEngine[engineID]!)
      #expect(scores.map { $0 == nil } == expected.map { $0 == nil })
      for (a, b) in zip(scores, expected) {
        if let a, let b { worst = max(worst, abs(a - b)) }
      }
      #expect(
        SoundComparisonScoring.flags(scores: scores, words: pair.refWords, cfg)
          == pair.flags(labEngine[engineID]!))
      checked += 1
    }
    guard checked > 0 else { return }
    print("Sound comparison golden logits \(engineID): \(checked) pairs, max |score − lab| \(worst)")
    #expect(worst < 0.05)
  }
}

#if canImport(CoreML) && canImport(AVFoundation)
@Suite("Sound comparison parity", .serialized)
struct SoundComparisonParityTests {
  /// Skipped unless the engine is installed (`scripts/setup-sound-comparison.sh`) and the lab's
  /// golden set is present, so it never runs in CI. Robust pairs (decision margin ≥ 0.5) must give
  /// the lab's flags exactly, and at least 95 % of all pairs must.
  @Test("Installed engines give the lab's flags on the golden pairs", arguments: ["lite", "full"])
  func goldenParity(engineID: String) async throws {
    guard installed(engineID) else { return }
    let engine = try await PhoneModelSoundComparisonEngine.load(
      installedAt: engineRoot.appendingPathComponent(engineID))
    let pairs = try GoldenPair.loadAll()
    let lab = labEngine[engineID]!
    var same = 0
    var robust = 0
    var robustSame = 0
    var worst = 0.0
    var seconds: [Double] = []
    for pair in pairs {
      let referenceSamples = try SoundComparisonAudio.load(
        LabPaths.root.appendingPathComponent(pair.refWAV))
      let takeSamples = try SoundComparisonAudio.load(
        LabPaths.root.appendingPathComponent(pair.takeWAV))
      let reference = try engine.analyzeReference(samples: referenceSamples, words: pair.refWords)
      let clock = ContinuousClock()
      var result: SoundComparisonResult?
      let elapsed = try clock.measure {
        result = try engine.compare(
          reference: reference, takeSamples: takeSamples, takeWords: pair.takeWords)
      }
      let flags = result!.flags.map(\.wordIndex)
      let ok = flags == pair.flags(lab)
      if ok { same += 1 }
      if pair.robust(lab) {
        robust += 1
        if ok { robustSame += 1 }
      }
      if !ok { print("  \(engineID) \(pair.id): \(flags) vs lab \(pair.flags(lab))") }
      for (a, b) in zip(result!.words.map(\.score), pair.scores(lab)) {
        if let a, let b { worst = max(worst, abs(a - b)) }
      }
      let compareSeconds =
        Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
      seconds.append(compareSeconds / (Double(takeSamples.count) / 16_000) * 10)
    }
    let median = seconds.sorted()[seconds.count / 2]
    print(
      "Sound comparison parity \(engineID): \(same)/\(pairs.count) pairs, robust \(robustSame)/\(robust),"
        + " max |score − lab| \(String(format: "%.4f", worst)),"
        + " compare \(String(format: "%.0f", median * 1000)) ms per 10 s of golden take (median)")

    // A real 10 s take: the golden takes end to end, against the first pair's Reference.
    var long: [Float] = []
    for pair in pairs where long.count < 160_000 {
      long += try SoundComparisonAudio.load(LabPaths.root.appendingPathComponent(pair.takeWAV))
    }
    long = Array(long.prefix(160_000))
    let first = try #require(pairs.first)
    let reference = try engine.analyzeReference(
      samples: SoundComparisonAudio.load(LabPaths.root.appendingPathComponent(first.refWAV)),
      words: first.refWords)
    let runs = try (0..<3).map { _ in
      try ContinuousClock().measure {
        _ = try engine.compare(reference: reference, takeSamples: long, takeWords: first.takeWords)
      }
    }.sorted()
    print("Sound comparison latency \(engineID): \(runs[1]) to compare a 10 s take (median of 3)")
    #expect(robustSame == robust)
    #expect(Double(same) >= 0.95 * Double(pairs.count))
  }
}
#endif
