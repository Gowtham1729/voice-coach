import Testing
import VoiceCoachCore

@Suite("Insight copy rules")
struct InsightCopyRulesTests {
  @Test("Placeholder pause rewrite is accepted; frozen strings also pass")
  func pausePlaceholdersPass() {
    let packet = FrozenHeroCatalog.pause.packet()
    let accepted = InsightCopyRules.acceptedObservation(
      rewrite: InsightCopyTestSamples.pauseRewrite,
      packet: packet
    )
    #expect(accepted?.summary == InsightCopyTestSamples.pauseRewrite.observation)
    #expect(accepted?.action == InsightCopyTestSamples.pauseRewrite.action)

    let frozen = InsightCopyRules.acceptedObservation(
      rewrite: InsightCopyRewrite(
        observation: FrozenCoachCopy.pauseSummary,
        action: FrozenCoachCopy.pauseAction
      ),
      packet: packet
    )
    #expect(frozen == packet.frozen)
  }

  @Test("Placeholder pitch rewrite is accepted")
  func pitchPlaceholderPasses() {
    let packet = FrozenHeroCatalog.pitch.packet()
    let accepted = InsightCopyRules.acceptedObservation(
      rewrite: InsightCopyTestSamples.pitchRewrite,
      packet: packet
    )
    #expect(accepted?.summary == InsightCopyTestSamples.pitchRewrite.observation)
  }

  @Test("Sanitize rejects length, markup, and wrapping junk")
  func sanitizeRejects() {
    let packet = FrozenHeroCatalog.pause.packet()
    #expect(
      InsightCopyRules.acceptedObservation(
        rewrite: InsightCopyRewrite(observation: "Short", action: FrozenCoachCopy.pauseAction),
        packet: packet
      ) == nil
    )
    #expect(
      InsightCopyRules.acceptedObservation(
        rewrite: InsightCopyRewrite(
          observation: "Pauses ran long. See https://example.com for tips on this take please.",
          action: FrozenCoachCopy.pauseAction
        ),
        packet: packet
      ) == nil
    )
  }

  @Test("Clinical and psych language is denied")
  func denyList() {
    let packet = FrozenHeroCatalog.pause.packet()
    #expect(
      InsightCopyRules.acceptedObservation(
        rewrite: InsightCopyRewrite(
          observation: "Your pauses show anxiety and low confidence on this take.",
          action: "On the next take, keep gaps between phrases shorter."
        ),
        packet: packet
      ) == nil
    )
    #expect(
      InsightCopyRules.acceptedObservation(
        rewrite: InsightCopyRewrite(
          observation: "Pauses may mean a medical throat diagnosis on this take.",
          action: "On the next take, keep gaps between phrases shorter."
        ),
        packet: packet
      ) == nil
    )
  }

  @Test("Invented numbers and units are rejected")
  func inventedNumbers() {
    let packet = FrozenHeroCatalog.pause.packet()
    #expect(
      InsightCopyRules.acceptedObservation(
        rewrite: InsightCopyRewrite(
          observation: "Pauses averaged 890 ms in the middle of this take.",
          action: "On the next take, keep gaps between phrases shorter."
        ),
        packet: packet
      ) == nil
    )
    #expect(
      InsightCopyRules.acceptedObservation(
        rewrite: InsightCopyRewrite(
          observation: "Pauses ran two times longer than this take needs.",
          action: "On the next take, keep gaps between phrases shorter."
        ),
        packet: packet
      ) == nil
    )
  }

  @Test("Pause rewrite cannot invent a pitch claim")
  func pauseAxisContainment() {
    let packet = FrozenHeroCatalog.pause.packet()
    #expect(
      InsightCopyRules.acceptedObservation(
        rewrite: InsightCopyRewrite(
          observation: "Pauses ran long and your pitch stayed too narrow on this take.",
          action: "On the next take, keep gaps between phrases shorter."
        ),
        packet: packet
      ) == nil
    )
  }

  @Test("Pitch rewrite cannot invent a pause claim")
  func pitchAxisContainment() {
    let packet = FrozenHeroCatalog.pitch.packet()
    #expect(
      InsightCopyRules.acceptedObservation(
        rewrite: InsightCopyRewrite(
          observation: "Pitch stayed narrow and pauses ran long on this take.",
          action: "On the next take, vary pitch more on the key words."
        ),
        packet: packet
      ) == nil
    )
  }
}
