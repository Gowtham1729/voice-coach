import Testing
import VoiceCoachCore

@Suite("Coach observation")
struct CoachObservationTests {
  @Test("Study fixture triggers pause-primary insight with character-exact copy")
  func studyFixtureTriggersPausePrimary() {
    let studyMetrics = CoreTestFixtures.metrics(
      internalPauseCount: 4,
      meanInternalPauseMs: 890.0,
      pitchRangeSemitones: 10.0,
      phraseDecayDB: 0.0
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

  @Test("Pitch narrow template fires with character-exact copy")
  func pitchNarrowExactCopy() {
    let flatPitchMetrics = CoreTestFixtures.metrics(
      pitchRangeSemitones: 2.1
    )

    let observation = CoachObservation.from(metrics: flatPitchMetrics)
    #expect(observation != nil)
    #expect(observation?.eyebrow == "Insight")
    #expect(
      observation?.summary
        == "Your pitch stayed in a narrow range — the line sounds flat."
    )
    #expect(
      observation?.action
        == "On the next take, vary pitch more on the key words."
    )
  }

  @Test("Phrase-end drop is not a default hero even when decay is strong")
  func phraseEndDropNotPrimaryHero() {
    let dropMetrics = CoreTestFixtures.metrics(
      phraseDecayDB: -8.0
    )

    #expect(CoachObservation.from(metrics: dropMetrics) == nil)
  }

  @Test("Boundary threshold tests for pause and pitch gates")
  func boundaryThresholds() {
    // --- Pause boundaries ---
    let atPauseThreshold = CoreTestFixtures.metrics(
      internalPauseCount: 2,
      meanInternalPauseMs: 700.0
    )
    #expect(CoachObservation.from(metrics: atPauseThreshold) != nil)

    let belowPauseDuration = CoreTestFixtures.metrics(
      internalPauseCount: 2,
      meanInternalPauseMs: 699.0
    )
    #expect(CoachObservation.from(metrics: belowPauseDuration) == nil)

    let singleLongPause = CoreTestFixtures.metrics(
      internalPauseCount: 1,
      meanInternalPauseMs: 900.0
    )
    #expect(CoachObservation.from(metrics: singleLongPause) == nil)

    let frequentShortPauses = CoreTestFixtures.metrics(
      internalPauseCount: 5,
      meanInternalPauseMs: 400.0
    )
    #expect(CoachObservation.from(metrics: frequentShortPauses) == nil)

    let zeroPauses = CoreTestFixtures.metrics(
      internalPauseCount: 0,
      meanInternalPauseMs: 0.0
    )
    #expect(CoachObservation.from(metrics: zeroPauses) == nil)

    // --- Pitch boundaries ---
    let atPitchThreshold = CoreTestFixtures.metrics(
      pitchRangeSemitones: 3.0
    )
    #expect(CoachObservation.from(metrics: atPitchThreshold)?.summary
      == "Your pitch stayed in a narrow range — the line sounds flat.")

    let abovePitchThreshold = CoreTestFixtures.metrics(
      pitchRangeSemitones: 3.1
    )
    #expect(CoachObservation.from(metrics: abovePitchThreshold) == nil)

    let widePitch = CoreTestFixtures.metrics(
      pitchRangeSemitones: 10.0
    )
    #expect(CoachObservation.from(metrics: widePitch) == nil)

    let nilPitch = CoreTestFixtures.metrics(
      pitchRangeSemitones: nil
    )
    #expect(CoachObservation.from(metrics: nilPitch) == nil)

    // --- Phrase decay must not become a hero ---
    let strongPhraseOnly = CoreTestFixtures.metrics(
      phraseDecayDB: -4.0
    )
    #expect(CoachObservation.from(metrics: strongPhraseOnly) == nil)

    let strongerPhraseOnly = CoreTestFixtures.metrics(
      phraseDecayDB: -12.0
    )
    #expect(CoachObservation.from(metrics: strongerPhraseOnly) == nil)
  }

  @Test("Primary pick ranks highest severity among pause and pitch")
  func primaryPickRanking() {
    // Strong pause beats mild pitch
    let strongPauseMetrics = CoreTestFixtures.metrics(
      internalPauseCount: 3,
      meanInternalPauseMs: 1400.0,
      pitchRangeSemitones: 2.4
    )
    let strongPauseObs = CoachObservation.from(metrics: strongPauseMetrics)
    #expect(
      strongPauseObs?.summary
        == "Your pauses averaged longer than this take needs — especially mid-phrase."
    )

    // Strong pitch beats mild pause
    let strongPitchMetrics = CoreTestFixtures.metrics(
      internalPauseCount: 3,
      meanInternalPauseMs: 770.0,
      pitchRangeSemitones: 0.6
    )
    let strongPitchObs = CoachObservation.from(metrics: strongPitchMetrics)
    #expect(
      strongPitchObs?.summary
        == "Your pitch stayed in a narrow range — the line sounds flat."
    )

    // Strong phrase decay must not beat pause — phrase is not a hero
    let pauseWithStrongPhrase = CoreTestFixtures.metrics(
      internalPauseCount: 2,
      meanInternalPauseMs: 840.0,
      phraseDecayDB: -8.0
    )
    let pauseWins = CoachObservation.from(metrics: pauseWithStrongPhrase)
    #expect(
      pauseWins?.summary
        == "Your pauses averaged longer than this take needs — especially mid-phrase."
    )

    // Equal severity pause vs pitch → pause wins tie-break
    let twoWayTie = CoreTestFixtures.metrics(
      internalPauseCount: 2,
      meanInternalPauseMs: 1050.0,
      pitchRangeSemitones: 1.5,
      phraseDecayDB: -12.0
    )
    let twoWayObs = CoachObservation.from(metrics: twoWayTie)
    #expect(
      twoWayObs?.summary
        == "Your pauses averaged longer than this take needs — especially mid-phrase."
    )

    // Pitch alone still wins when pause does not fire; phrase decay ignored
    let pitchWithPhrase = CoreTestFixtures.metrics(
      pitchRangeSemitones: 1.5,
      phraseDecayDB: -6.0
    )
    let pitchObs = CoachObservation.from(metrics: pitchWithPhrase)
    #expect(
      pitchObs?.summary
        == "Your pitch stayed in a narrow range — the line sounds flat."
    )
  }

  @Test("Parked phrase-end Content strings preserved for later conditional rule")
  func parkedPhraseEndCopyPreserved() {
    #expect(ParkedCoachObservationCopy.phraseEndSummary == "Your energy dropped at the phrase end.")
    #expect(
      ParkedCoachObservationCopy.phraseEndAction
        == "On the next take, keep the last words as strong as the start."
    )
  }
}
