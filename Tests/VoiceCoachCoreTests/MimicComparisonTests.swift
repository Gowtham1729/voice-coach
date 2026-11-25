import Testing
import VoiceCoachCore

@Suite("Mimic comparison")
struct MimicComparisonTests {
  @Test("Matching transcripts produce reliable aligned pairs")
  func matchingTranscripts() {
    let reference = CoreTestFixtures.session()
    let attempt = CoreTestFixtures.session()

    let comparison = MimicComparison.compare(reference: reference, attempt: attempt)

    #expect(comparison.status == .ok)
    #expect(comparison.correspondenceReliable)
    #expect(comparison.pairs.map(\.word) == ["clear", "steady", "voice"])
  }

  @Test("Missing transcripts are reported without fabricated pairs")
  func missingTranscript() {
    let reference = CoreTestFixtures.session()
    let attempt = PracticeSession(
      audioURL: reference.audioURL,
      result: CoreTestFixtures.analysis()
    )

    let comparison = MimicComparison.compare(reference: reference, attempt: attempt)

    #expect(comparison.status == .missingTranscript)
    #expect(comparison.pairs.isEmpty)
  }

  @Test(
    "Quality gates override otherwise matching alignment",
    arguments: [
      (snrDB: 5.0, clipping: 0.0, expected: MimicAlignmentStatus.poorSnr),
      (snrDB: 20.0, clipping: 3.5, expected: MimicAlignmentStatus.clipping),
    ]
  )
  func qualityGates(snrDB: Double, clipping: Double, expected: MimicAlignmentStatus) {
    let reference = CoreTestFixtures.session()
    let attempt = CoreTestFixtures.session(snrDB: snrDB, clippingPercent: clipping)

    #expect(MimicComparison.compare(reference: reference, attempt: attempt).status == expected)
  }

  @Test("One unmatched word each between two matched words is heard differently")
  func heardDifferently() {
    let reference = CoreTestFixtures.session(words: ["the", "ship", "sails", "away"])
    let heard = CoreTestFixtures.session(words: ["the", "sheep", "sails", "away"])
    let swapped = MimicComparison.compare(reference: reference, attempt: heard)
    #expect(
      swapped.heardDifferently.map { [$0.reference.word, $0.attempt.word] } == [["ship", "sheep"]])
    // Not a Practice next target on its own.
    #expect(
      CoachingPlanner.mimic(reference: reference, attempt: heard).focus?.referenceWordIndex != 1)

    let twoForOne = MimicComparison.compare(
      reference: CoreTestFixtures.session(
        words: ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]),
      attempt: CoreTestFixtures.session(
        words: ["a", "x", "y", "c", "d", "e", "f", "g", "h", "i", "j"]))
    #expect(twoForOne.status == .ok)
    #expect(twoForOne.heardDifferently.isEmpty)

    let noisy = MimicComparison.compare(
      reference: reference,
      attempt: CoreTestFixtures.session(words: ["the", "sheep", "sails", "away"], snrDB: 3))
    #expect(noisy.heardDifferently.isEmpty)

    let anchors = (1...12).map { "w\($0)" }
    var left = anchors
    var right = anchors
    for slot in [1, 5, 9, 13] {  // after w1, w4, w7, w10
      left.insert("ref\(slot)", at: slot)
      right.insert("heard\(slot)", at: slot)
    }
    let many = MimicComparison.compare(
      reference: CoreTestFixtures.session(words: left),
      attempt: CoreTestFixtures.session(words: right))
    #expect(many.status == .ok)
    #expect(many.heardDifferently.map(\.reference.word) == ["ref1", "ref5", "ref9"])
  }
}
