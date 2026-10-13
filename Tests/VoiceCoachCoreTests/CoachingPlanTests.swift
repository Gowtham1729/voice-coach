import Foundation
import Testing
import VoiceCoachCore

@Suite("Coaching plan")
struct CoachingPlanTests {
  @Test("A usable recording has metrics only, with no practice targets")
  func ordinaryRecording() {
    let metrics = CoreTestFixtures.metrics(
      duration: 12.12, internalPauseCount: 5, meanInternalPauseMs: 288,
      pitchRangeSemitones: 9.22)

    let plan = CoachingPlanner.recording(current: metrics)

    #expect(plan.signals.isEmpty)
    #expect(plan.notice == nil)
  }

  @Test("A poor recording is a notice, not a practice exercise")
  func poorRecording() {
    let clipped = CoachingPlanner.recording(current: CoreTestFixtures.metrics(
      clippingPercent: 2.5, internalPauseCount: 3,
      meanInternalPauseMs: 900, pitchRangeSemitones: 8))
    #expect(clipped.signals.isEmpty)
    #expect(clipped.notice == "2.5% of this take's samples clipped.")

    let severeNoise = CoachingPlanner.recording(current: CoreTestFixtures.metrics(
      snrDB: 3.9, internalPauseCount: 3, meanInternalPauseMs: 410,
      pitchRangeSemitones: 0.3))
    #expect(severeNoise.signals.isEmpty)
    #expect(
      severeNoise.notice
        == "Speech was 3.9 dB above the measured noise floor. Pitch and pause estimates may be unreliable."
    )

    let unmeasured = CoachingPlanner.recording(current: CoreTestFixtures.metrics(
      snrDB: .nan, clippingPercent: .nan))
    #expect(unmeasured.notice == "This take did not provide a dependable recording-quality measurement.")
  }

  @Test("Reliable Mimic feedback uses reference timing and voiced word pitch")
  func mimicTargets() {
    let reference = makeTake(
      starts: [0.3, 0.7, 1.1, 1.5, 1.9, 2.3],
      pitchAtImportant: 4, energyAtSpeaker: 4)
    let previous = makeTake(
      starts: [0.9, 1.5, 2.1, 2.7, 3.3, 4.1],
      pitchAtImportant: -5, energyAtSpeaker: -2)
    let attempt = makeTake(
      starts: [0.9, 1.4, 1.9, 2.4, 3.0, 3.6],
      pitchAtImportant: -3, energyAtSpeaker: -2)

    let plan = CoachingPlanner.mimic(reference: reference, attempt: attempt, previous: previous)

    #expect(plan.signals.count == 2)
    let timing = plan.signals.first { $0.id == "mimic.timing" }
    let pitch = plan.signals.first { $0.id == "mimic.pitch.4" }
    #expect(timing?.observation.contains("reference") == true)
    #expect(timing?.action.contains("pace across the phrase") == true)
    #expect(timing?.action.contains("transition into") == true)
    #expect(timing?.progress?.contains("previous take") == true)
    #expect(pitch?.observation.contains("important") == true)
    #expect(pitch?.progress?.contains("previous take") == true)
    #expect(CoachingPlanner.mimic(reference: reference, attempt: attempt)
      .signals.allSatisfy { $0.progress == nil })

    let truncatedPrevious = makeTake(
      starts: [1.5, 2.1, 2.7, 3.3, 4.1],
      tokens: ["speaker", "should", "shape", "important", "words"])
    let unmatchedSpan = CoachingPlanner.mimic(
      reference: reference, attempt: attempt, previous: truncatedPrevious)
    #expect(unmatchedSpan.signals.first { $0.id == "mimic.timing" }?.progress == nil)
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
    #expect(plan.signals[0].progress?.contains("Closer than the previous take") == true)
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
      starts: starts, pitchByWord: [4: -7], energyByWord: [0: -5, 1: -4, 2: -4, 3: -5])

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

    #expect(plan.signals.isEmpty)
    #expect(plan.notice == "Word matching is too limited for a reference comparison.")
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

  @Test("Retry selection uses 2.5 st and 3.5 dB gates; empty gate has no cue")
  func retrySelectionGate() {
    let starts = [0.3, 0.7, 1.1, 1.5, 1.9, 2.3]
    let reference = makeTake(starts: starts)
    let pitchGate = makeTake(starts: starts, pitchAtImportant: 2.5)
    let loudnessGate = makeTake(starts: starts, energyAtSpeaker: 3.5)
    let belowGate = makeTake(starts: starts, energyAtSpeaker: 3.3)

    #expect(CoachingPlanner.mimic(reference: reference, attempt: pitchGate).focus?.kind == .pitch)
    #expect(CoachingPlanner.mimic(reference: reference, attempt: loudnessGate).focus?.kind == .loudness)
    #expect(CoachingPlanner.mimic(reference: reference, attempt: belowGate).focus == nil)
  }

  @Test("Verifiable close needs two consecutive takes")
  func retryCloseStreak() {
    let starts = [0.3, 0.7, 1.1, 1.5, 1.9, 2.3]
    let reference = makeTake(starts: starts)
    let first = makeTake(starts: starts, pitchAtImportant: 6)
    let close = makeTake(starts: starts, pitchAtImportant: 1)
    let target = CoachingPlanner.mimic(reference: reference, attempt: first).focus!
    let firstClose = CoachingPlanner.evaluateRetry(
      reference: reference, attempt: close, pinnedTarget: target)
    #expect(firstClose.verdict == .withinNoise)
    #expect(firstClose.nextConsecutiveCloseTakes == 1)

    let carried = TargetFocus(
      referenceWordIndex: target.referenceWordIndex, word: target.word,
      kind: target.kind, gap: firstClose.newGap!,
      referenceRange: target.referenceRange, takeRange: target.takeRange,
      originalGap: target.originalGap,
      consecutiveCloseTakes: firstClose.nextConsecutiveCloseTakes)
    let secondClose = CoachingPlanner.evaluateRetry(
      reference: reference, attempt: close, pinnedTarget: carried)
    #expect(secondClose.verdict == .closeEnough)
    let drift = CoachingPlanner.evaluateRetry(
      reference: reference, attempt: makeTake(starts: starts, pitchAtImportant: 4),
      pinnedTarget: carried)
    #expect(drift.nextConsecutiveCloseTakes == 0)
    let afterDrift = TargetFocus(
      referenceWordIndex: target.referenceWordIndex, word: target.word,
      kind: target.kind, gap: drift.newGap!,
      referenceRange: target.referenceRange, takeRange: target.takeRange,
      originalGap: target.originalGap,
      consecutiveCloseTakes: drift.nextConsecutiveCloseTakes)
    #expect(CoachingPlanner.evaluateRetry(
      reference: reference, attempt: close, pinnedTarget: afterDrift).verdict == .withinNoise)

  }

  @Test("Non-verifiable target never renders a measured verdict")
  func nonVerifiableRetryHasNoVerdict() {
    let starts = [0.3, 0.7, 1.1, 1.5, 1.9, 2.3]
    let reference = makeTake(starts: starts)
    let first = makeTake(starts: starts, pitchAtImportant: 3)
    let current = makeTake(starts: starts, pitchAtImportant: 0.5)
    let target = CoachingPlanner.mimic(reference: reference, attempt: first).focus!
    #expect(!target.isVerifiable)
    let result = CoachingPlanner.evaluateRetry(reference: reference, attempt: current, pinnedTarget: target)
    #expect(result.verdict == .neutral)
    #expect(result.verdictCopy == nil)
    #expect(result.verdict != .withinNoise)
    #expect(OneTargetRetryStrings.neutralRetryLine(word: target.word)
      == "We can’t measure a difference this small. Compare ‘important’ by ear.")
  }

  @Test("Neutral chips use previous, current, and reference word ranges")
  func neutralReplayUsesThreeWordRanges() {
    let starts = [0.3, 0.7, 1.1, 1.5, 1.9, 2.3]
    let reference = makeTake(starts: starts)
    let first = makeTake(
      starts: [0.3, 0.7, 1.1, 1.5, 2.0, 2.4], pitchAtImportant: 3)
    let current = makeTake(starts: [0.3, 0.7, 1.1, 1.5, 2.1, 2.5], pitchAtImportant: 2.8)
    let initial = CoachingPlanner.mimic(reference: reference, attempt: first).focus!
    let target = TargetFocus(
      referenceWordIndex: initial.referenceWordIndex, word: initial.word,
      kind: initial.kind, gap: initial.gap,
      referenceRange: initial.referenceRange, takeRange: initial.takeRange,
      previousTakeID: first.id, previousTakeRange: initial.takeRange)
    let result = CoachingPlanner.evaluateRetry(reference: reference, attempt: current, pinnedTarget: target)
    let spans = result.neutralReplaySpans
    #expect(spans?.previousTakeID == first.id)
    #expect(spans?.previous == 2.0...2.25)
    #expect(spans?.current == 2.1...2.35)
    #expect(spans?.reference == 1.9...2.15)

    let unaligned = makeTake(
      starts: [0.3, 0.7, 1.1, 1.5, 2.3],
      tokens: ["Every", "speaker", "should", "shape", "words"])
    let missing = CoachingPlanner.evaluateRetry(
      reference: reference, attempt: unaligned, pinnedTarget: target)
    #expect(missing.verdict == .neutral)
    #expect(missing.verdictCopy == nil)
    #expect(missing.neutralReplaySpans?.current == nil)
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
