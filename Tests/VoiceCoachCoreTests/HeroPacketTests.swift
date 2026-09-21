import Testing
import VoiceCoachCore

@Suite("Hero packet")
struct HeroPacketTests {
  @Test("Pause fixture selects pause claim and frozen copy")
  func pauseFixture() {
    let metrics = CoreTestFixtures.metrics(
      internalPauseCount: 4,
      meanInternalPauseMs: 890.0,
      pitchRangeSemitones: 10.0
    )
    let packet = HeroPacket.from(metrics: metrics)
    #expect(packet != nil)
    #expect(packet?.isValid == true)
    #expect(packet?.axis == .pause)
    #expect(packet?.claimID == .pauseLongMidPhrase)
    #expect(packet?.actionID == .pauseShortenPhraseGaps)
    #expect(packet?.canonicalObservation == FrozenCoachCopy.pauseSummary)
    #expect(packet?.canonicalAction == FrozenCoachCopy.pauseAction)
    #expect(packet?.frozen == CoachObservation.from(metrics: metrics))
    #expect(
      packet?.frozen.summary
        == "Your pauses averaged longer than this take needs — especially mid-phrase."
    )
  }

  @Test("Monotone pitch fixture selects pitch claim and frozen copy")
  func pitchFixture() {
    let metrics = CoreTestFixtures.metrics(pitchRangeSemitones: 2.1)
    let packet = HeroPacket.from(metrics: metrics)
    #expect(packet?.isValid == true)
    #expect(packet?.axis == .pitch)
    #expect(packet?.claimID == .pitchNarrowRange)
    #expect(packet?.actionID == .pitchVaryKeyWords)
    #expect(
      packet?.frozen.summary
        == "Your pitch stayed in a narrow range — the line sounds flat."
    )
  }

  @Test("Mismatched claim and action IDs fail Gate 0")
  func mismatchedIDsAreInvalid() {
    let packet = HeroPacket(
      axis: .pause,
      claimID: .pauseLongMidPhrase,
      actionID: .pitchVaryKeyWords,
      canonicalObservation: FrozenCoachCopy.pauseSummary,
      canonicalAction: FrozenCoachCopy.pauseAction,
      frozen: CoachObservation(
        summary: FrozenCoachCopy.pauseSummary,
        action: FrozenCoachCopy.pauseAction
      )
    )
    #expect(packet.isValid == false)
  }

  @Test("Non-hero metric changes do not change pause packet identity")
  func counterfactualNonHeroMetrics() {
    let base = CoreTestFixtures.metrics(
      internalPauseCount: 4,
      meanInternalPauseMs: 890.0,
      pitchRangeSemitones: 10.0,
      snrDB: 20
    )
    let varied = CoreTestFixtures.metrics(
      internalPauseCount: 4,
      meanInternalPauseMs: 890.0,
      pitchRangeSemitones: 10.0,
      snrDB: 8,
      phraseDecayDB: -12.0
    )
    let a = HeroPacket.from(metrics: base)
    let b = HeroPacket.from(metrics: varied)
    #expect(a?.claimID == b?.claimID)
    #expect(a?.actionID == b?.actionID)
    #expect(a?.canonicalObservation == b?.canonicalObservation)
  }

  @Test("Prompt carries canonical copy only, not raw VoiceMetrics")
  func promptOmitsRawMetrics() {
    let metrics = CoreTestFixtures.metrics(
      internalPauseCount: 4,
      meanInternalPauseMs: 890.0,
      pitchRangeSemitones: 10.0
    )
    let packet = try #require(HeroPacket.from(metrics: metrics))
    let prompt = InsightCopyPrompt.userMessage(for: packet)
    #expect(prompt.contains(packet.canonicalObservation))
    #expect(prompt.contains(packet.canonicalAction))
    #expect(prompt.contains("pause"))
    #expect(!prompt.contains("890"))
    #expect(!prompt.contains("VoiceMetrics"))
    #expect(!prompt.contains("internalPause"))
    #expect(!prompt.contains("meanInternalPauseMs"))
    #expect(!prompt.contains("snr"))
    #expect(!prompt.contains(packet.claimID.rawValue))
  }
}
