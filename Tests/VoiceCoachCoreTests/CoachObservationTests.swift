import Testing
import VoiceCoachCore

@Suite("Coach observation")
struct CoachObservationTests {
  @Test("Study fixture triggers pause-primary insight with character-exact copy")
  func studyFixtureTriggersPausePrimary() {
    let studyMetrics = CoreTestFixtures.metrics(
      internalPauseCount: 4,
      meanInternalPauseMs: 890.0
    )

    let observation = CoachObservation.from(metrics: studyMetrics)
    #expect(observation != nil)
    #expect(observation?.eyebrow == "Insight")
    #expect(
      observation?.summary
        == "Your pauses averaged longer than this take needs — especially mid-phrase."
    )
    #expect(
      observation?.action
        == "On the next take, aim for shorter gaps between phrases."
    )
  }

  @Test("Boundary threshold tests for pause-primary derivation")
  func boundaryThresholds() {
    // Exactly at threshold: count == 2, mean == 700ms -> triggers
    let atThreshold = CoreTestFixtures.metrics(
      internalPauseCount: 2,
      meanInternalPauseMs: 700.0
    )
    #expect(CoachObservation.from(metrics: atThreshold) != nil)

    // Just below duration threshold: count == 2, mean == 699ms -> nil
    let belowDuration = CoreTestFixtures.metrics(
      internalPauseCount: 2,
      meanInternalPauseMs: 699.0
    )
    #expect(CoachObservation.from(metrics: belowDuration) == nil)

    // Insufficient pause count: count == 1, mean == 900ms -> nil (single pause is not a pattern)
    let singleLongPause = CoreTestFixtures.metrics(
      internalPauseCount: 1,
      meanInternalPauseMs: 900.0
    )
    #expect(CoachObservation.from(metrics: singleLongPause) == nil)

    // Frequent short pauses: count == 5, mean == 400ms -> nil (within normal conversational range)
    let frequentShortPauses = CoreTestFixtures.metrics(
      internalPauseCount: 5,
      meanInternalPauseMs: 400.0
    )
    #expect(CoachObservation.from(metrics: frequentShortPauses) == nil)

    // Zero pauses baseline -> nil
    let zeroPauses = CoreTestFixtures.metrics(
      internalPauseCount: 0,
      meanInternalPauseMs: 0.0
    )
    #expect(CoachObservation.from(metrics: zeroPauses) == nil)
  }
}
