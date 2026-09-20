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
}
