import Foundation

/// Two evidence-backed practice targets. This is a view model, never part of report JSON.
public struct CoachingPlan: Equatable, Sendable {
  public let signals: [CoachingSignal]
  public let limitation: String?

  public init(signals: [CoachingSignal], limitation: String? = nil) {
    self.signals = signals
    self.limitation = limitation
  }
}

public struct CoachingSignal: Equatable, Sendable {
  public let id: String
  public let title: String
  public let observation: String
  public let action: String
  public let progress: String?
  /// Terms a model-written action must retain. The observed fact is never model-written.
  public let actionTerms: [String]

  public init(
    id: String, title: String, observation: String, action: String,
    progress: String? = nil, actionTerms: [String]
  ) {
    self.id = id
    self.title = title
    self.observation = observation
    self.action = action
    self.progress = progress
    self.actionTerms = actionTerms
  }
}

/// Computes coaching from the current audio and, when comparable, the previous retained take.
/// Thresholds select which measured difference deserves attention; they are not norms for a voice.
public enum CoachingPlanner {
  public static func recording(
    current: VoiceMetrics, previous: VoiceMetrics? = nil
  ) -> CoachingPlan {
    var candidates: [(priority: Double, signal: CoachingSignal)] = []

    if current.clippingPercent.isFinite, current.clippingPercent >= 1 {
      candidates.append((10, CoachingSignal(
        id: "recording.clipping", title: "Recording level",
        observation: "\(number(current.clippingPercent, 1))% of this take's samples clipped.",
        action: "Move a little farther from the microphone or lower input gain, then record again.",
        progress: change(current.clippingPercent, previous?.clippingPercent, unit: "% clipping"),
        actionTerms: ["microphone"]
      )))
    } else if current.snrDB.isFinite, current.snrDB < 10 {
      candidates.append((10, CoachingSignal(
        id: "recording.noise", title: "Recording noise",
        observation: "Speech was \(number(current.snrDB, 1)) dB above the measured noise floor.",
        action: "Try a quieter spot or move closer to the microphone, then record again.",
        progress: change(current.snrDB, previous?.snrDB, unit: "dB SNR"),
        actionTerms: ["microphone"]
      )))
    }

    if !current.snrDB.isFinite || current.snrDB < 6
      || !current.clippingPercent.isFinite || current.clippingPercent >= 3
    {
      let quality = candidates.first?.signal ?? CoachingSignal(
        id: "recording.quality", title: "Recording quality",
        observation: "This take did not provide a dependable recording-quality measurement.",
        action: "Check the microphone setup and record the same phrase again.",
        actionTerms: ["record"]
      )
      return CoachingPlan(signals: [quality, CoachingSignal(
        id: "recording.retry", title: "Listen back",
        observation: "Pitch and pause estimates may be unreliable at this recording quality.",
        action: "Listen for masked or distorted words, then record the same phrase again.",
        actionTerms: ["listen", "record"]
      )])
    }

    let pauseCount = max(0, current.internalPauseCount)
    let pauseMean = current.meanInternalPauseMs
    if pauseCount >= 2, pauseMean.isFinite, pauseMean >= 700 {
      candidates.append((4 + pauseMean / 700, CoachingSignal(
        id: "recording.longPauses", title: "Long breaks",
        observation: "\(pauseCount) internal pauses averaged \(number(pauseMean, 0)) ms.",
        action: "Try joining the words within each phrase, then leave a deliberate break between ideas.",
        progress: change(pauseMean, previous?.meanInternalPauseMs, unit: "ms average pause"),
        actionTerms: ["phrase"]
      )))
    } else {
      let observation: String
      if pauseCount == 0 {
        observation = "No internal pauses were detected in this take."
      } else if pauseMean.isFinite {
        observation = "\(pauseCount) internal pauses averaged \(number(pauseMean, 0)) ms."
      } else {
        observation = "Pause timing could not be measured reliably in this take."
      }
      candidates.append((1, CoachingSignal(
        id: "recording.pausePlacement", title: "Pause placement",
        observation: observation,
        action: "Listen for a natural break between ideas and place one there on the next take.",
        actionTerms: ["break"]
      )))
    }

    if let range = current.pitchRangeSemitones, range.isFinite, range >= 0 {
      if range <= 3 {
        candidates.append((4 + (3 - range) / 3, CoachingSignal(
          id: "recording.narrowPitch", title: "Pitch movement",
          observation: "Measured pitch spanned \(number(range, 1)) semitones in this take.",
          action: "Choose one key word to lift in pitch, then let the phrase settle naturally.",
          progress: change(range, previous?.pitchRangeSemitones, unit: "st pitch range"),
          actionTerms: ["pitch"]
        )))
      } else {
        candidates.append((1, CoachingSignal(
          id: "recording.pitchShape", title: "Pitch shape",
          observation: "Measured pitch spanned \(number(range, 1)) semitones in this take.",
          action: "Choose a key word for a deliberate pitch lift, then compare it with the surrounding words.",
          actionTerms: ["pitch"]
        )))
      }
    } else {
      candidates.append((1, CoachingSignal(
        id: "recording.expression", title: "Word emphasis",
        observation: "This take did not yield enough voiced pitch data for a pitch target.",
        action: "Pick one important word and make it stand out relative to its neighbors on the next take.",
        actionTerms: ["word"]
      )))
    }

    candidates.sort { $0.priority > $1.priority }
    return CoachingPlan(signals: Array(candidates.prefix(2).map(\.signal)))
  }

  public static func mimic(
    reference: PracticeSession, attempt: PracticeSession, previous: PracticeSession? = nil
  ) -> CoachingPlan {
    let comparison = MimicComparison.compare(reference: reference, attempt: attempt)
    guard comparison.correspondenceReliable, comparison.pairs.count >= 5 else {
      let limitation: String
      switch comparison.status {
      case .poorSnr, .clipping:
        limitation = "Reference comparison is limited by recording quality. These targets use this take only."
      default:
        limitation = "Word matching is too limited for reference claims. These targets use this take only."
      }
      let general = recording(current: attempt.result.metrics)
      return CoachingPlan(signals: general.signals, limitation: limitation)
    }

    let prior = previous.map { MimicComparison.compare(reference: reference, attempt: $0) }
    let previousComparison = prior?.correspondenceReliable == true ? prior : nil
    var candidates: [(priority: Double, signal: CoachingSignal)] = []

    if let timing = timingDrift(comparison.pairs) {
      let drift = timing.driftMs
      let substantial = abs(drift) >= 250 && abs(drift) >= timing.referenceSpanMs * 0.06
      let previousDrift = previousComparison.flatMap { previous -> Double? in
        guard previous.pairs.first?.referenceIndex == comparison.pairs.first?.referenceIndex,
          previous.pairs.last?.referenceIndex == comparison.pairs.last?.referenceIndex
        else { return nil }
        return timingDrift(previous.pairs)?.driftMs
      }
      let direction = drift > 0 ? "longer" : "shorter"
      let observation = substantial
        ? "From first to last matched word, this take ran \(number(abs(drift) / 1_000, 1)) s \(direction) than the reference."
        : "From first to last matched word, timing was within \(number(abs(drift), 0)) ms of the reference."
      let transition = timing.largestSlipWord
      let action: String
      if substantial, let transition {
        action = "Replay the transition into “\(transition)” and bring that word closer to the reference timing."
      } else {
        action = "Repeat the phrase at the reference pace, then check where the last word lands."
      }
      candidates.append((substantial ? 6 + abs(drift) / max(500, timing.referenceSpanMs) : 0.8,
        CoachingSignal(
          id: "mimic.timing", title: "Phrase timing", observation: observation, action: action,
          progress: previousDrift.map {
            mimicProgress(previousGap: abs($0) / 1_000, currentGap: abs(drift) / 1_000,
              unit: "s", tolerance: 0.15)
          },
          actionTerms: transition.map {
            [normalized($0), "timing|pace|sooner|later"]
          } ?? ["pace|timing"]
        )))
    }

    if let pitch = strongestWordGap(
      comparison.pairs, reference: reference, attempt: attempt, kind: .pitch
    ) {
      let delta = pitch.delta
      let word = pitch.pair.word
      let needsAdjustment = abs(delta) >= 2.5
      let priorDelta = previous.flatMap { previous in
        previousComparison?.pairs.first(where: {
          $0.referenceIndex == pitch.pair.referenceIndex
        }).flatMap { validDelta($0, reference: reference, attempt: previous, kind: .pitch) }
      }
      let observation = needsAdjustment
        ? "On “\(word),” relative pitch was \(number(abs(delta), 1)) st \(delta < 0 ? "below" : "above") the reference."
        : "On “\(word),” relative pitch was within \(number(abs(delta), 1)) st of the reference."
      let action = needsAdjustment
        ? "Replay “\(word)” and \(delta < 0 ? "lift" : "lower") its pitch relative to the surrounding words."
        : "Keep the pitch shape around “\(word)” when you repeat the phrase."
      let actionTerms = needsAdjustment
        ? [normalized(word), "pitch", delta < 0 ? "lift|raise|higher" : "lower|drop"]
        : [normalized(word), "pitch"]
      candidates.append((needsAdjustment ? 4 + abs(delta) / 3 : 0.7, CoachingSignal(
        id: "mimic.pitch.\(pitch.pair.referenceIndex)", title: "Pitch on “\(word)”",
        observation: observation,
        action: action,
        progress: priorDelta.map {
          mimicProgress(previousGap: abs($0), currentGap: abs(delta), unit: "st",
            tolerance: 0.5)
        },
        actionTerms: actionTerms
      )))
    }

    if let energy = strongestWordGap(
      comparison.pairs, reference: reference, attempt: attempt, kind: .energy
    ) {
      let delta = energy.delta
      let word = energy.pair.word
      let needsAdjustment = abs(delta) >= 3.5
      let priorDelta = previous.flatMap { previous in
        previousComparison?.pairs.first(where: {
          $0.referenceIndex == energy.pair.referenceIndex
        }).flatMap { validDelta($0, reference: reference, attempt: previous, kind: .energy) }
      }
      let observation = needsAdjustment
        ? "On “\(word),” relative word energy was \(number(abs(delta), 1)) dB \(delta < 0 ? "below" : "above") the reference."
        : "On “\(word),” relative word energy was within \(number(abs(delta), 1)) dB of the reference."
      let action = needsAdjustment
        ? "Replay “\(word)” and \(delta < 0 ? "strengthen" : "soften") it relative to the surrounding words."
        : "Keep the emphasis on “\(word)” when you repeat the phrase."
      let actionTerms = needsAdjustment
        ? [normalized(word), delta < 0 ? "strengthen|stress|emphas" : "soften|less|reduce"]
        : [normalized(word), "emphasis|stress"]
      candidates.append((needsAdjustment ? 3 + abs(delta) / 4 : 0.6, CoachingSignal(
        id: "mimic.emphasis.\(energy.pair.referenceIndex)", title: "Emphasis on “\(word)”",
        observation: observation,
        action: action,
        progress: priorDelta.map {
          mimicProgress(previousGap: abs($0), currentGap: abs(delta), unit: "dB",
            tolerance: 1)
        },
        actionTerms: actionTerms
      )))
    }

    candidates.sort { $0.priority > $1.priority }
    var signals = Array(candidates.prefix(2).map(\.signal))
    if signals.count < 2 {
      let general = recording(current: attempt.result.metrics)
      for signal in general.signals where signals.count < 2 && !signals.contains(where: { $0.id == signal.id }) {
        signals.append(signal)
      }
    }
    return CoachingPlan(signals: signals)
  }

  private enum WordGapKind { case pitch, energy }

  private static func strongestWordGap(
    _ pairs: [MimicWordPair], reference: PracticeSession, attempt: PracticeSession,
    kind: WordGapKind
  ) -> (pair: MimicWordPair, delta: Double)? {
    pairs.compactMap { pair -> (pair: MimicWordPair, delta: Double)? in
      guard isPracticeWord(pair.word),
        let delta = validDelta(pair, reference: reference, attempt: attempt, kind: kind)
      else { return nil }
      return (pair, delta)
    }.max { abs($0.delta) < abs($1.delta) }
  }

  private static func validDelta(
    _ pair: MimicWordPair, reference: PracticeSession, attempt: PracticeSession,
    kind: WordGapKind
  ) -> Double? {
    guard reference.words.indices.contains(pair.referenceIndex),
      attempt.words.indices.contains(pair.attemptIndex),
      min(pair.reference.end - pair.reference.start, pair.attempt.end - pair.attempt.start) >= 0.15
    else { return nil }
    let left = reference.words[pair.referenceIndex]
    let right = attempt.words[pair.attemptIndex]
    switch kind {
    case .pitch:
      guard left.pitch.pitchCoverage >= 0.45, right.pitch.pitchCoverage >= 0.45,
        left.pitch.validPitchFrames >= 8, right.pitch.validPitchFrames >= 8,
        let referencePitch = pair.referencePitch,
        let attemptPitch = pair.attemptPitch
      else { return nil }
      let delta = attemptPitch - referencePitch
      guard delta.isFinite else { return nil }
      return delta
    case .energy:
      guard left.loudness.activeFrameCoverage >= 0.6,
        right.loudness.activeFrameCoverage >= 0.6,
        let referenceEnergy = pair.referenceEnergy,
        let attemptEnergy = pair.attemptEnergy
      else { return nil }
      let delta = attemptEnergy - referenceEnergy
      guard delta.isFinite else { return nil }
      return delta
    }
  }

  private static func timingDrift(_ pairs: [MimicWordPair])
    -> (driftMs: Double, referenceSpanMs: Double, largestSlipWord: String?)?
  {
    guard let first = pairs.first, let last = pairs.last else { return nil }
    let referenceSpan = (last.reference.end - first.reference.start) * 1_000
    let attemptSpan = (last.attempt.end - first.attempt.start) * 1_000
    guard referenceSpan.isFinite, attemptSpan.isFinite, referenceSpan >= 2_000 else { return nil }
    let offsets = pairs.map { ($0.attempt.start - $0.reference.start) * 1_000 }
    let drift = attemptSpan - referenceSpan
    func directionalSlip(at index: Int) -> Double {
      let step = offsets[index] - offsets[index - 1]
      return drift >= 0 ? step : -step
    }
    let largest = offsets.indices.dropFirst().max {
      directionalSlip(at: $0) < directionalSlip(at: $1)
    }
    let slipWord = largest.flatMap {
      directionalSlip(at: $0) >= 180 ? pairs[$0].word : nil
    }
    return (drift, referenceSpan, slipWord)
  }

  private static let functionWords: Set<String> = [
    "a", "an", "and", "are", "as", "at", "be", "for", "from", "had", "has", "in", "is",
    "it", "its", "of", "on", "or", "over", "the", "this", "to", "was", "were", "what",
  ]

  private static func isPracticeWord(_ word: String) -> Bool {
    let cleaned = normalized(word)
    return cleaned.count >= 4 && !functionWords.contains(cleaned)
  }

  private static func normalized(_ word: String) -> String {
    word.lowercased().unicodeScalars.filter {
      CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
    }.map(String.init).joined()
  }

  private static func number(_ value: Double, _ digits: Int) -> String {
    String(format: "%.*f", digits, value)
  }

  private static func change(_ current: Double, _ previous: Double?, unit: String) -> String? {
    guard let previous, previous.isFinite, current.isFinite else { return nil }
    return "Previous attempt: \(number(previous, 1)) \(unit); now \(number(current, 1))."
  }

  private static func mimicProgress(
    previousGap: Double, currentGap: Double, unit: String, tolerance: Double
  ) -> String {
    let direction: String
    if previousGap - currentGap >= tolerance {
      direction = "Closer than the previous attempt"
    } else if currentGap - previousGap >= tolerance {
      direction = "Farther from the reference than the previous attempt"
    } else {
      direction = "Similar to the previous attempt"
    }
    return "\(direction): \(number(previousGap, 1)) → \(number(currentGap, 1)) \(unit) apart."
  }
}
