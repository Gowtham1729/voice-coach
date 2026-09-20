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

  @Test("Phrase-end drop template fires with character-exact copy")
  func phraseEndDropExactCopy() {
    let dropMetrics = CoreTestFixtures.metrics(
      phraseDecayDB: -6.5
    )

    let observation = CoachObservation.from(metrics: dropMetrics)
    #expect(observation != nil)
    #expect(observation?.eyebrow == "Insight")
    #expect(
      observation?.summary
        == "Your energy dropped at the phrase end."
    )
    #expect(
      observation?.action
        == "On the next take, keep the last words as strong as the start."
    )
  }

  @Test("Boundary threshold tests for all observation gates")
  func boundaryThresholds() {
    // --- Pause boundaries ---
    // Exactly at threshold: count == 2, mean == 700ms -> triggers
    let atPauseThreshold = CoreTestFixtures.metrics(
      internalPauseCount: 2,
      meanInternalPauseMs: 700.0
    )
    #expect(CoachObservation.from(metrics: atPauseThreshold) != nil)

    // Just below duration threshold: count == 2, mean == 699ms -> nil
    let belowPauseDuration = CoreTestFixtures.metrics(
      internalPauseCount: 2,
      meanInternalPauseMs: 699.0
    )
    #expect(CoachObservation.from(metrics: belowPauseDuration) == nil)

    // Insufficient pause count: count == 1, mean == 900ms -> nil
    let singleLongPause = CoreTestFixtures.metrics(
      internalPauseCount: 1,
      meanInternalPauseMs: 900.0
    )
    #expect(CoachObservation.from(metrics: singleLongPause) == nil)

    // Frequent short pauses: count == 5, mean == 400ms -> nil
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

    // --- Pitch boundaries ---
    // Exactly at threshold: 3.0 st -> triggers
    let atPitchThreshold = CoreTestFixtures.metrics(
      pitchRangeSemitones: 3.0
    )
    #expect(CoachObservation.from(metrics: atPitchThreshold)?.summary
      == "Your pitch stayed in a narrow range — the line sounds flat.")

    // Just above threshold: 3.1 st -> nil
    let abovePitchThreshold = CoreTestFixtures.metrics(
      pitchRangeSemitones: 3.1
    )
    #expect(CoachObservation.from(metrics: abovePitchThreshold) == nil)

    // Wide pitch range (study-like 10.0 st) -> nil
    let widePitch = CoreTestFixtures.metrics(
      pitchRangeSemitones: 10.0
    )
    #expect(CoachObservation.from(metrics: widePitch) == nil)

    // Nil pitch range -> nil
    let nilPitch = CoreTestFixtures.metrics(
      pitchRangeSemitones: nil
    )
    #expect(CoachObservation.from(metrics: nilPitch) == nil)

    // --- Phrase decay boundaries ---
    // Exactly at threshold: -4.0 dB -> triggers
    let atPhraseThreshold = CoreTestFixtures.metrics(
      phraseDecayDB: -4.0
    )
    #expect(CoachObservation.from(metrics: atPhraseThreshold)?.summary
      == "Your energy dropped at the phrase end.")

    // Just above threshold (less negative): -3.9 dB -> nil
    let abovePhraseThreshold = CoreTestFixtures.metrics(
      phraseDecayDB: -3.9
    )
    #expect(CoachObservation.from(metrics: abovePhraseThreshold) == nil)

    // Healthy ending: 0.0 dB -> nil
    let healthyPhrase = CoreTestFixtures.metrics(
      phraseDecayDB: 0.0
    )
    #expect(CoachObservation.from(metrics: healthyPhrase) == nil)
  }

  @Test("Primary pick ranks highest severity candidate and resolves ties stably")
  func primaryPickRanking() {
    // Strong pause (severity = (1400 - 700) / 700 = 1.0) beats mild pitch (range 2.4, severity = (3 - 2.4)/3 = 0.2)
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

    // Strong pitch (range 0.6, severity = (3 - 0.6)/3 = 0.8) beats mild pause (mean 770ms, severity = (770 - 700)/700 = 0.1)
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

    // Strong phrase-end drop (decay -8.0 dB, severity = (8 - 4)/4 = 1.0) beats mild pause (mean 840ms, severity = 0.2)
    let strongPhraseMetrics = CoreTestFixtures.metrics(
      internalPauseCount: 2,
      meanInternalPauseMs: 840.0,
      phraseDecayDB: -8.0
    )
    let strongPhraseObs = CoachObservation.from(metrics: strongPhraseMetrics)
    #expect(
      strongPhraseObs?.summary
        == "Your energy dropped at the phrase end."
    )

    // Stable tie-break: equal severity (severity = 0.5 each for pause, pitch, phrase)
    // pause: (1050 - 700) / 700 = 0.5
    // pitch: (3.0 - 1.5) / 3.0 = 0.5
    // phrase: (6.0 - 4.0) / 4.0 = 0.5
    // Pause should win over pitch and phrase
    let threeWayTie = CoreTestFixtures.metrics(
      internalPauseCount: 2,
      meanInternalPauseMs: 1050.0,
      pitchRangeSemitones: 1.5,
      phraseDecayDB: -6.0
    )
    let threeWayObs = CoachObservation.from(metrics: threeWayTie)
    #expect(
      threeWayObs?.summary
        == "Your pauses averaged longer than this take needs — especially mid-phrase."
    )

    // Pitch vs Phrase tie-break (pause not firing): pitch wins over phrase
    let pitchPhraseTie = CoreTestFixtures.metrics(
      pitchRangeSemitones: 1.5,
      phraseDecayDB: -6.0
    )
    let pitchPhraseObs = CoachObservation.from(metrics: pitchPhraseTie)
    #expect(
      pitchPhraseObs?.summary
        == "Your pitch stayed in a narrow range — the line sounds flat."
    )
  }
}
