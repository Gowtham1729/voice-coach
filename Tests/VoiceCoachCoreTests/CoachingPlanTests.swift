import Foundation
import Testing
import VoiceCoachCore

@Suite("Coaching plan")
struct CoachingPlanTests {
  @Test("A normal take still offers two factual practice targets")
  func ordinaryTakeWithoutHero() {
    let metrics = CoreTestFixtures.metrics(
      duration: 12.12, internalPauseCount: 5, meanInternalPauseMs: 288,
      pitchRangeSemitones: 9.22)

    let plan = CoachingPlanner.recording(current: metrics)

    #expect(plan.signals.count == 2)
    #expect(Set(plan.signals.map(\.id)) == ["recording.pausePlacement", "recording.pitchShape"])
    #expect(plan.signals.contains { $0.observation.contains("288") })
    #expect(plan.signals.contains { $0.observation.contains("9.2") })
    #expect(plan.signals.allSatisfy { !$0.action.isEmpty })
  }

  @Test("Recording quality displaces a neutral target, not both targets")
  func poorRecording() {
    let metrics = CoreTestFixtures.metrics(
      clippingPercent: 2.5, internalPauseCount: 3,
      meanInternalPauseMs: 900, pitchRangeSemitones: 8)
    let plan = CoachingPlanner.recording(current: metrics)

    #expect(plan.signals.count == 2)
    #expect(plan.signals[0].id == "recording.clipping")
    #expect(plan.signals[1].id == "recording.longPauses")

    let severeNoise = CoachingPlanner.recording(current: CoreTestFixtures.metrics(
      snrDB: 3.9, internalPauseCount: 3, meanInternalPauseMs: 410,
      pitchRangeSemitones: 0.3))
    #expect(severeNoise.signals.map(\.id) == ["recording.noise", "recording.retry"])
    #expect(!severeNoise.signals.contains { $0.id == "recording.narrowPitch" })
  }

  @Test("Reliable Mimic feedback uses reference timing and voiced word pitch")
  func mimicTargets() {
    let reference = makeTake(
      starts: [0.3, 0.7, 1.1, 1.5, 1.9, 2.3],
      pitchAtImportant: 4, energyAtSpeaker: 4)
    let previous = makeTake(
      starts: [0.9, 1.5, 2.1, 2.7, 3.3, 4.1],
      pitchAtImportant: -3, energyAtSpeaker: -2)
    let attempt = makeTake(
      starts: [0.9, 1.4, 1.9, 2.4, 3.0, 3.6],
      pitchAtImportant: -1, energyAtSpeaker: -2)

    let plan = CoachingPlanner.mimic(reference: reference, attempt: attempt, previous: previous)

    #expect(plan.signals.count == 2)
    #expect(plan.signals[0].id == "mimic.timing")
    #expect(plan.signals[0].observation.contains("reference"))
    #expect(plan.signals[0].progress?.contains("previous attempt") == true)
    #expect(plan.signals[1].id == "mimic.pitch.4")
    #expect(plan.signals[1].observation.contains("important"))
    #expect(plan.signals[1].progress?.contains("previous attempt") == true)
    #expect(CoachingPlanner.mimic(reference: reference, attempt: attempt)
      .signals.allSatisfy { $0.progress == nil })

    let truncatedPrevious = makeTake(
      starts: [1.5, 2.1, 2.7, 3.3, 4.1],
      tokens: ["speaker", "should", "shape", "important", "words"])
    let unmatchedSpan = CoachingPlanner.mimic(
      reference: reference, attempt: attempt, previous: truncatedPrevious)
    #expect(unmatchedSpan.signals[0].progress == nil)
  }

  @Test("Missing or unreliable alignment never produces word-level claims")
  func unreliableMimic() {
    let reference = makeTake(starts: [0.3, 0.7, 1.1, 1.5, 1.9, 2.3])
    let attempt = PracticeSession(
      audioURL: URL(fileURLWithPath: "/tmp/missing-words.wav"),
      result: CoreTestFixtures.analysis(duration: 5))

    let plan = CoachingPlanner.mimic(reference: reference, attempt: attempt)

    #expect(plan.signals.count == 2)
    #expect(plan.limitation != nil)
    #expect(plan.signals.allSatisfy { $0.id.hasPrefix("recording.") })
  }

  @Test("Close Mimic matches are maintained, not corrected in the wrong direction")
  func closeMimic() {
    let reference = makeTake(starts: [0.3, 0.7, 1.1, 1.5, 1.9, 2.3])
    let attempt = makeTake(starts: [0.3, 0.7, 1.1, 1.5, 1.9, 2.3])

    let plan = CoachingPlanner.mimic(reference: reference, attempt: attempt)

    #expect(plan.signals.count == 2)
    #expect(plan.signals[0].observation.contains("within"))
    #expect(plan.signals[1].action.contains("Keep"))
    #expect(!plan.signals[1].action.contains("lower"))
  }

  @Test("Model wording retains target and direction without invented targets")
  func actionValidation() {
    let signal = CoachingSignal(
      id: "mimic.pitch.4", title: "Pitch", observation: "Measured pitch differed.",
      action: "Lift pitch on important.",
      actionTerms: ["important", "pitch", "lift|raise|higher"])

    #expect(CoachingActionRules.accepted(
      "Raise pitch on important relative to nearby words.", for: signal) != nil)
    #expect(CoachingActionRules.accepted(
      "Lower pitch on important relative to nearby words.", for: signal) == nil)
    #expect(CoachingActionRules.accepted(
      "Raise pitch on a different word.", for: signal) == nil)
    #expect(CoachingActionRules.accepted(
      "Raise pitch exactly 5 semitones on important.", for: signal) == nil)
    #expect(CoachingActionRules.accepted(
      "Use throat therapy to raise pitch on important.", for: signal) == nil)
    #expect(CoachingActionRules.accepted(
      "Raise pitch on important, then repeat the invented phrase 'clear signal'.", for: signal) == nil)
  }

  private func makeTake(
    starts: [Double], tokens: [String] = ["Every", "speaker", "should", "shape", "important", "words"],
    pitchAtImportant: Double = 0, energyAtSpeaker: Double = 0
  ) -> PracticeSession {
    let transcriptWords = zip(tokens, starts).map { token, start in
      TranscriptWord(word: token, start: start, end: start + 0.25, confidence: 0.98)
    }
    let words = transcriptWords.enumerated().map { index, word in
      WordAnalysis(
        word: word.word, start: word.start, end: word.end,
        pitch: WordPitchMetrics(
          medianHz: 160, relativeMedianSemitones: index == 4 ? pitchAtImportant : 0,
          rangeSemitones: 2, startToEndSemitones: 0,
          validPitchFrames: 15, pitchCoverage: 0.9),
        loudness: WordLoudnessMetrics(
          relativeMeanDB: index == 1 ? energyAtSpeaker : 0,
          startToEndDB: 0, activeFrameCoverage: 0.9)
      )
    }
    return PracticeSession(
      audioURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).wav"),
      result: CoreTestFixtures.analysis(duration: 5),
      transcription: TranscriptionResult(text: tokens.joined(separator: " "), words: transcriptWords),
      words: words
    )
  }
}
