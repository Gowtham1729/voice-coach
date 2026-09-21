import Testing
import VoiceCoachCore

@Suite("Insight copy resolver")
struct InsightCopyResolverTests {
  @Test("Pause fixture fail-closes to frozen copy when generator is nil")
  func pauseFixtureNilGenerator() async {
    let metrics = CoreTestFixtures.metrics(
      internalPauseCount: 4,
      meanInternalPauseMs: 890.0,
      pitchRangeSemitones: 10.0
    )
    let resolver = InsightCopyResolver(generator: nil)
    let resolved = await resolver.resolve(metrics: metrics)
    let frozen = CoachObservation.from(metrics: metrics)
    #expect(resolved == frozen)
    #expect(
      resolved?.summary
        == "Your pauses averaged longer than this take needs — especially mid-phrase."
    )
    #expect(resolved?.action == "On the next take, aim for shorter gaps between phrases.")
  }

  @Test("Monotone pitch fixture fail-closes to frozen copy when unavailable")
  func pitchFixtureUnavailable() async {
    let metrics = CoreTestFixtures.metrics(pitchRangeSemitones: 2.1)
    let stub = StubInsightCopyGenerator(availability: .unavailable)
    let resolver = InsightCopyResolver(generator: stub)
    let resolved = await resolver.resolve(metrics: metrics)
    #expect(resolved == CoachObservation.from(metrics: metrics))
    #expect(
      resolved?.summary
        == "Your pitch stayed in a narrow range — the line sounds flat."
    )
    #expect(stub.rewriteCalls == 0)
  }

  @Test("Generator nil rewrite fail-closes to frozen pause copy")
  func generatorReturnsNil() async {
    let metrics = CoreTestFixtures.metrics(
      internalPauseCount: 4,
      meanInternalPauseMs: 890.0
    )
    let stub = StubInsightCopyGenerator(availability: .available, rewriteResult: nil)
    let resolver = InsightCopyResolver(generator: stub)
    let resolved = await resolver.resolve(metrics: metrics)
    #expect(resolved == CoachObservation.from(metrics: metrics))
    #expect(stub.rewriteCalls == 1)
  }

  @Test("Sanitize reject fail-closes to frozen copy")
  func sanitizeReject() async {
    let metrics = CoreTestFixtures.metrics(
      internalPauseCount: 4,
      meanInternalPauseMs: 890.0
    )
    let stub = StubInsightCopyGenerator(
      rewriteResult: InsightCopyRewrite(
        observation: "Medical anxiety diagnosis with 890 ms pauses.",
        action: "Please fix your throat and pitch."
      )
    )
    let resolver = InsightCopyResolver(generator: stub)
    let resolved = await resolver.resolve(metrics: metrics)
    #expect(resolved == CoachObservation.from(metrics: metrics))
    #expect(
      resolved?.summary
        == "Your pauses averaged longer than this take needs — especially mid-phrase."
    )
  }

  @Test("Euphemism deny rejects fail-close to frozen copy")
  func euphemismDenyRejectsFailClose() async {
    let metrics = CoreTestFixtures.metrics(
      internalPauseCount: 4,
      meanInternalPauseMs: 890.0
    )
    let worriedStub = StubInsightCopyGenerator(
      rewriteResult: InsightCopyRewrite(
        observation: "You sounded worried when pauses ran long between phrases.",
        action: "On the next take, keep gaps between phrases shorter."
      )
    )
    let worriedResolver = InsightCopyResolver(generator: worriedStub)
    let worriedResolved = await worriedResolver.resolve(metrics: metrics)
    #expect(worriedResolved == CoachObservation.from(metrics: metrics))
    #expect(
      worriedResolved?.summary
        == "Your pauses averaged longer than this take needs — especially mid-phrase."
    )

    let confidenceStub = StubInsightCopyGenerator(
      rewriteResult: InsightCopyRewrite(
        observation: "You lacked confidence when pauses ran long between phrases.",
        action: "On the next take, keep gaps between phrases shorter."
      )
    )
    let confidenceResolver = InsightCopyResolver(generator: confidenceStub)
    let confidenceResolved = await confidenceResolver.resolve(metrics: metrics)
    #expect(confidenceResolved == CoachObservation.from(metrics: metrics))
    #expect(
      confidenceResolved?.summary
        == "Your pauses averaged longer than this take needs — especially mid-phrase."
    )
  }

  @Test("Accepted rewrite is returned and cached")
  func acceptedRewriteIsCached() async throws {
    let metrics = CoreTestFixtures.metrics(
      internalPauseCount: 4,
      meanInternalPauseMs: 890.0
    )
    let stub = StubInsightCopyGenerator(rewriteResult: InsightCopyTestSamples.pauseRewrite)
    let cache = InMemoryInsightCopyCache()
    let resolver = InsightCopyResolver(
      generator: stub,
      cache: cache,
      localeIdentifier: { "en_US" }
    )
    let first = await resolver.resolve(metrics: metrics)
    #expect(first?.summary == InsightCopyTestSamples.pauseRewrite.observation)
    #expect(first?.action == InsightCopyTestSamples.pauseRewrite.action)

    let second = await resolver.resolve(metrics: metrics)
    #expect(second == first)
    #expect(stub.rewriteCalls == 1)

    let key = try #require(HeroPacket.from(metrics: metrics)?.cacheKey(locale: "en_US"))
    #expect(cache.observation(for: key) == first)
  }

  @Test("Accepted pitch rewrite is returned")
  func acceptedPitchRewriteReturned() async {
    let metrics = CoreTestFixtures.metrics(pitchRangeSemitones: 2.1)
    let stub = StubInsightCopyGenerator(rewriteResult: InsightCopyTestSamples.pitchRewrite)
    let resolver = InsightCopyResolver(generator: stub)
    let resolved = await resolver.resolve(metrics: metrics)
    #expect(resolved?.summary == InsightCopyTestSamples.pitchRewrite.observation)
    #expect(resolved?.action == InsightCopyTestSamples.pitchRewrite.action)
    #expect(stub.rewriteCalls == 1)
  }

  @Test("Disabled wording layer uses frozen copy and skips the generator")
  func disabledUsesFrozen() async {
    let metrics = CoreTestFixtures.metrics(
      internalPauseCount: 4,
      meanInternalPauseMs: 890.0
    )
    let stub = StubInsightCopyGenerator(rewriteResult: InsightCopyTestSamples.pauseRewrite)
    let resolver = InsightCopyResolver(generator: stub, isEnabled: { false })
    let resolved = await resolver.resolve(metrics: metrics)
    #expect(resolved == CoachObservation.from(metrics: metrics))
    #expect(stub.rewriteCalls == 0)
  }

  @Test("Invalid packet never calls the generator")
  func invalidPacketSkipsGenerator() async {
    let stub = StubInsightCopyGenerator(rewriteResult: InsightCopyTestSamples.pauseRewrite)
    let resolver = InsightCopyResolver(generator: stub)
    let invalid = HeroPacket(
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
    let resolved = await resolver.resolve(packet: invalid)
    #expect(resolved == invalid.frozen)
    #expect(stub.rewriteCalls == 0)
  }

  @Test("No hero still returns nil — fail-closed does not invent coaching")
  func noHeroRemainsNil() async {
    let metrics = CoreTestFixtures.metrics(phraseDecayDB: -8.0)
    let stub = StubInsightCopyGenerator(rewriteResult: InsightCopyTestSamples.pauseRewrite)
    let resolver = InsightCopyResolver(generator: stub)
    let resolved = await resolver.resolve(metrics: metrics)
    #expect(resolved == nil)
    #expect(CoachObservation.from(metrics: metrics) == nil)
    #expect(stub.rewriteCalls == 0)
  }

  @Test("Cache key differs by locale and policy version")
  func cacheKeyIdentity() {
    let packet = FrozenHeroCatalog.pause.packet()
    let en = packet.cacheKey(locale: "en_US")
    let fr = packet.cacheKey(locale: "fr_FR")
    #expect(en != fr)
    let otherVersion = HeroPacket(
      axis: packet.axis,
      claimID: packet.claimID,
      actionID: packet.actionID,
      canonicalObservation: packet.canonicalObservation,
      canonicalAction: packet.canonicalAction,
      frozen: packet.frozen,
      copyPolicyVersion: InsightCopyPolicy.version + 1
    )
    #expect(otherVersion.isValid == false)
    #expect(otherVersion.cacheKey(locale: "en_US") != en)
  }
}
