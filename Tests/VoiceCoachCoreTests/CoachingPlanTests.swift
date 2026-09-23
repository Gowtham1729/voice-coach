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
    #expect(plan.signals[0].action.contains("pace across the phrase"))
    #expect(plan.signals[0].action.contains("transition into"))
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

  @Test("Repeated pitch gaps become a phrase target with a word checkpoint")
  func repeatedPitchPattern() {
    let starts = [0.3, 0.7, 1.1, 1.5, 1.9, 2.3]
    let reference = makeTake(starts: starts)
    let previous = makeTake(starts: starts, pitchByWord: [0: 5, 1: 5, 2: 5, 3: 5])
    let attempt = makeTake(starts: starts, pitchByWord: [0: 3, 1: 4, 2: 3.5, 3: 4])

    let plan = CoachingPlanner.mimic(reference: reference, attempt: attempt, previous: previous)

    #expect(plan.signals[0].id == "mimic.pitchPattern")
    #expect(plan.signals[0].observation.contains("4 of 6 measured content words"))
    #expect(plan.signals[0].observation.contains("“speaker”"))
    #expect(plan.signals[0].action.contains("across the phrase"))
    #expect(plan.signals[0].action.contains("“speaker”"))
    #expect(plan.signals[0].progress?.contains("Closer than the previous attempt") == true)
    #expect(CoachingActionRules.accepted(
      "Follow the reference's pitch movement across the phrase, using ‘speaker’ as a checkpoint.",
      for: plan.signals[0]) != nil)
    #expect(CoachingActionRules.accepted(
      "Focus pitch only on the word speaker for the next take.",
      for: plan.signals[0]) == nil)
  }

  @Test("Repeated energy gaps use phrase emphasis; one pitch outlier stays word specific")
  func patternVersusWord() {
    let starts = [0.3, 0.7, 1.1, 1.5, 1.9, 2.3]
    let reference = makeTake(starts: starts)
    let attempt = makeTake(
      starts: starts, pitchByWord: [4: -5], energyByWord: [0: -5, 1: -4, 2: -4, 3: -5])

    let plan = CoachingPlanner.mimic(reference: reference, attempt: attempt)

    #expect(plan.signals.map(\.id) == ["mimic.pitch.4", "mimic.emphasisPattern"]
      || plan.signals.map(\.id) == ["mimic.emphasisPattern", "mimic.pitch.4"])
    #expect(plan.signals.contains { $0.observation.contains("4 of 6 measured content words") })
    #expect(plan.signals.contains { $0.title == "Pitch on “important”" })
  }

  @Test("A cluster of gaps in one short stretch is not called a phrase pattern")
  func clusteredPitchGaps() {
    let starts = (0..<10).map { 0.3 + Double($0) * 0.4 }
    let tokens = ["every", "speaker", "should", "the", "a", "in", "shape", "important", "words", "on"]
    let reference = makeTake(starts: starts, tokens: tokens)
    let attempt = makeTake(
      starts: starts, tokens: tokens, pitchByWord: [0: 4, 1: 4, 2: 4])

    let plan = CoachingPlanner.mimic(reference: reference, attempt: attempt)

    #expect(!plan.signals.contains { $0.id == "mimic.pitchPattern" })
    #expect(plan.signals.contains { $0.id.hasPrefix("mimic.pitch.") })
  }

  @Test("Word timing can drift locally even when total phrase length matches")
  func unevenTimingWithZeroNetDrift() {
    let reference = makeTake(starts: [0.3, 0.7, 1.1, 1.5, 1.9, 2.3])
    let attempt = makeTake(starts: [0.3, 1.0, 1.1, 1.8, 1.9, 2.3])

    let plan = CoachingPlanner.mimic(reference: reference, attempt: attempt)

    #expect(plan.signals[0].id == "mimic.timing")
    #expect(plan.signals[0].observation.contains("4 transitions"))
    #expect(plan.signals[0].action.contains("pace across the phrase"))
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
      "Raise pitch on the word important relative to nearby words.", for: signal) != nil)
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

    let placement = CoachingSignal(
      id: "recording.pausePlacement", title: "Pause placement", observation: "No pauses detected.",
      action: "Listen for a natural break between ideas and place one there on the next take.",
      actionTerms: ["break"])
    #expect(CoachingActionRules.accepted(
      "Find a natural break between ideas and pause there on the next take for the word pause.",
      for: placement) == nil)
  }

  private func makeTake(
    starts: [Double], tokens: [String] = ["Every", "speaker", "should", "shape", "important", "words"],
    pitchAtImportant: Double = 0, energyAtSpeaker: Double = 0,
    pitchByWord: [Int: Double] = [:], energyByWord: [Int: Double] = [:]
  ) -> PracticeSession {
    let transcriptWords = zip(tokens, starts).map { token, start in
      TranscriptWord(word: token, start: start, end: start + 0.25, confidence: 0.98)
    }
    let words = transcriptWords.enumerated().map { index, word in
      WordAnalysis(
        word: word.word, start: word.start, end: word.end,
        pitch: WordPitchMetrics(
          medianHz: 160,
          relativeMedianSemitones: pitchByWord[index] ?? (index == 4 ? pitchAtImportant : 0),
          rangeSemitones: 2, startToEndSemitones: 0,
          validPitchFrames: 15, pitchCoverage: 0.9),
        loudness: WordLoudnessMetrics(
          relativeMeanDB: energyByWord[index] ?? (index == 1 ? energyAtSpeaker : 0),
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
