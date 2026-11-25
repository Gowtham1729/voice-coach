import Foundation
import Testing
import VoiceCoachCore

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
    let first = try engine.compare(reference: reference, takeSamples: tone)
    let second = try engine.compare(reference: reference, takeSamples: tone)

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
}

// MARK: - App parity (PRD PR 2): the installed engines on the lab's golden pairs.

private let repoRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let lab = repoRoot.appendingPathComponent("build/pron-lab")
private let goldenFile = lab.appendingPathComponent("proto/eng_final/golden/pairs.json")
private let engineRoot = FileManager.default.urls(
  for: .applicationSupportDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("VoiceCoach/SoundComparison")
private func installed(_ id: String) -> Bool {
  FileManager.default.fileExists(
    atPath: engineRoot.appendingPathComponent("\(id)/manifest.json").path)
    && FileManager.default.fileExists(atPath: goldenFile.path)
}

#if canImport(CoreML) && canImport(AVFoundation)
@Suite("Sound comparison parity", .serialized)
struct SoundComparisonParityTests {
  /// Skipped unless the engine is installed (`scripts/setup-sound-comparison.sh`) and the lab's
  /// golden set is present, so it never runs in CI. At least 95 % of pairs must give the lab's
  /// flags.
  @Test("Installed engines give the lab's flags on the golden pairs", arguments: ["lite", "full"])
  func goldenParity(engineID: String) async throws {
    guard installed(engineID) else { return }
    let engine = try await PhoneModelSoundComparisonEngine.load(
      installedAt: engineRoot.appendingPathComponent(engineID))
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: goldenFile)) as? [String: Any])
    let pairs = try #require(root["pairs"] as? [[String: Any]])
    var same = 0
    for pair in pairs {
      let words = (pair["ref_words"] as? [[String: Any]] ?? []).map {
        SoundWord(
          text: $0["word"] as? String ?? "", start: ($0["start"] as? NSNumber)?.doubleValue,
          end: ($0["end"] as? NSNumber)?.doubleValue)
      }
      let reference = try engine.analyzeReference(
        samples: SoundComparisonAudio.load(lab.appendingPathComponent(pair["ref_wav"] as! String)),
        words: words)
      let result = try engine.compare(
        reference: reference,
        takeSamples: SoundComparisonAudio.load(
          lab.appendingPathComponent(pair["take_wav"] as! String)))
      let expected = ((pair["engines"] as? [String: [String: Any]])?[engineID]?["flags"]
        as? [NSNumber] ?? []).map(\.intValue)
      if result.flags.map(\.wordIndex) == expected { same += 1 }
    }
    print("Sound comparison parity \(engineID): \(same)/\(pairs.count) pairs give the lab's flags")
    #expect(Double(same) >= 0.95 * Double(pairs.count))
  }
}
#endif
