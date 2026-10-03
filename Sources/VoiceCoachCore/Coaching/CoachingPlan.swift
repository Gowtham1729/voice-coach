import Foundation

/// Mimic practice targets, or a short notice when a take cannot support them.
/// This is a view model, never part of report JSON.
public struct CoachingPlan: Equatable, Sendable {
  public let signals: [CoachingSignal]
  public let notice: String?

  public init(signals: [CoachingSignal] = [], notice: String? = nil) {
    self.signals = signals
    self.notice = notice
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

/// Selects Mimic practice targets from a reference comparison.
/// A free recording has no practice targets. It carries a notice only when clipping
/// or noise makes pitch and pause estimates hard to trust.
public enum CoachingPlanner {
  public static func recording(current: VoiceMetrics) -> CoachingPlan {
    CoachingPlan(notice: recordingNotice(current))
  }

  private static func recordingNotice(_ metrics: VoiceMetrics) -> String? {
    let clipping = metrics.clippingPercent
    let snr = metrics.snrDB
    let estimatesUnreliable = !snr.isFinite || snr < 6 || !clipping.isFinite || clipping >= 3
    if clipping.isFinite, clipping >= 1 {
      return qualityNotice(
        "\(number(clipping, 1))% of this take's samples clipped.",
        estimatesUnreliable: estimatesUnreliable)
    }
    if snr.isFinite, snr < 10 {
      return qualityNotice(
        "Speech was \(number(snr, 1)) dB above the measured noise floor.",
        estimatesUnreliable: estimatesUnreliable)
    }
    guard estimatesUnreliable else { return nil }
    if !clipping.isFinite, !snr.isFinite {
      return "This take did not provide a dependable recording-quality measurement."
    }
    return "Pitch and pause estimates may be unreliable at this recording quality."
  }

  private static func qualityNotice(_ measured: String, estimatesUnreliable: Bool) -> String {
    guard estimatesUnreliable else { return measured }
    return "\(measured) Pitch and pause estimates may be unreliable."
  }

  public static func mimic(
    reference: PracticeSession, attempt: PracticeSession, previous: PracticeSession? = nil
  ) -> CoachingPlan {
    let comparison = MimicComparison.compare(reference: reference, attempt: attempt)
    guard comparison.correspondenceReliable, comparison.pairs.count >= 5 else {
      let notice: String
      switch comparison.status {
      case .poorSnr, .clipping:
        notice = "Reference comparison is limited by recording quality."
      default:
        notice = "Word matching is too limited for a reference comparison."
      }
      return CoachingPlan(notice: notice)
    }

    let prior = previous.map { MimicComparison.compare(reference: reference, attempt: $0) }
    let previousComparison = prior?.correspondenceReliable == true ? prior : nil
    var candidates: [(priority: Double, signal: CoachingSignal)] = []

    if let timing = timingSummary(comparison.pairs) {
      let drift = timing.driftMs
      let substantial = abs(drift) >= 250 && abs(drift) >= timing.referenceSpanMs * 0.06
      let uneven = timing.largeTransitionCount >= 3 && timing.largeTransitionSpread >= 0.3
      let previousDrift = previousComparison.flatMap { previous -> Double? in
        guard previous.pairs.first?.referenceIndex == comparison.pairs.first?.referenceIndex,
          previous.pairs.last?.referenceIndex == comparison.pairs.last?.referenceIndex
        else { return nil }
        return timingSummary(previous.pairs)?.driftMs
      }
      let direction = drift > 0 ? "longer" : "shorter"
      let observation: String
      if substantial {
        observation = "From first to last matched word, this take ran \(number(abs(drift) / 1_000, 1)) s \(direction) than the reference."
      } else if uneven {
        observation = "Word-to-word timing differed by at least 180 ms at \(timing.largeTransitionCount) transitions, although the full matched span was within \(number(abs(drift), 0)) ms of the reference."
      } else {
        observation = "From first to last matched word, timing was within \(number(abs(drift), 0)) ms of the reference."
      }
      let transition = substantial ? timing.largestSlipWord : timing.largestVariationWord
      let action: String
      if (substantial || uneven), let transition {
        action = "Match the reference pace across the phrase, using the transition into “\(transition)” as a checkpoint."
      } else {
        action = "Repeat the phrase at the reference pace, then check where the last word lands."
      }
      let driftProgress = previousDrift.map {
        mimicProgress(previousGap: abs($0) / 1_000, currentGap: abs(drift) / 1_000,
          unit: "s", tolerance: 0.15)
      }
      let priority: Double
      let progress: String?
      if substantial {
        priority = 6 + abs(drift) / max(500, timing.referenceSpanMs)
        progress = driftProgress
      } else if uneven {
        priority = 5 + Double(timing.largeTransitionCount) / 10
        progress = unevenTimingProgress(current: timing, previous: previousComparison)
      } else {
        priority = 0.8
        progress = driftProgress
      }
      candidates.append((priority,
        CoachingSignal(
          id: "mimic.timing", title: "Phrase timing", observation: observation, action: action,
          progress: progress,
          actionTerms: transition.map {
            [normalized($0), "timing|pace|sooner|later", "phrase|across|throughout"]
          } ?? ["pace|timing", "phrase|across|throughout"]
        )))
    }

    let pitchGaps = wordGaps(
      comparison.pairs, reference: reference, attempt: attempt, kind: .pitch)
    if let pattern = repeatedPattern(
      in: pitchGaps, matchedWordCount: comparison.pairs.count, threshold: 2.5) {
      let examples = Array(pattern.sorted { abs($0.delta) > abs($1.delta) }.prefix(2))
      let medianGap = median(pattern.map { abs($0.delta) })
      let anchor = examples[0].pair.word
      let exampleText = patternExampleText(examples, unit: "st")
      candidates.append((4.5 + medianGap / 3, CoachingSignal(
        id: "mimic.pitchPattern", title: "Pitch across the phrase",
        observation: "Relative pitch differed by at least 2.5 st on \(pattern.count) of \(pitchGaps.count) measured content words; \(exampleText).",
        action: "Follow the reference's pitch movement across the phrase, using “\(anchor)” as a checkpoint.",
        progress: patternProgress(
          pattern, previous: previous, previousComparison: previousComparison,
          reference: reference, kind: .pitch, unit: "st", tolerance: 0.5),
        actionTerms: [normalized(anchor), "pitch", "phrase|across|throughout"]
      )))
    } else if let pitch = pitchGaps.max(by: { abs($0.delta) < abs($1.delta) }) {
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

    let energyGaps = wordGaps(
      comparison.pairs, reference: reference, attempt: attempt, kind: .energy)
    if let pattern = repeatedPattern(
      in: energyGaps, matchedWordCount: comparison.pairs.count, threshold: 3.5) {
      let examples = Array(pattern.sorted { abs($0.delta) > abs($1.delta) }.prefix(2))
      let medianGap = median(pattern.map { abs($0.delta) })
      let anchor = examples[0].pair.word
      let exampleText = patternExampleText(examples, unit: "dB")
      candidates.append((3.5 + medianGap / 4, CoachingSignal(
        id: "mimic.emphasisPattern", title: "Emphasis across the phrase",
        observation: "Relative word energy differed by at least 3.5 dB on \(pattern.count) of \(energyGaps.count) measured content words; \(exampleText).",
        action: "Follow the reference's emphasis across the phrase, using “\(anchor)” as a checkpoint.",
        progress: patternProgress(
          pattern, previous: previous, previousComparison: previousComparison,
          reference: reference, kind: .energy, unit: "dB", tolerance: 1),
        actionTerms: [normalized(anchor), "emphasis|stress", "phrase|across|throughout"]
      )))
    } else if let energy = energyGaps.max(by: { abs($0.delta) < abs($1.delta) }) {
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
    return CoachingPlan(signals: Array(candidates.prefix(2).map(\.signal)))
  }

  private enum WordGapKind { case pitch, energy }
  private struct WordGap {
    let pair: MimicWordPair
    let delta: Double
  }

  private static func wordGaps(
    _ pairs: [MimicWordPair], reference: PracticeSession, attempt: PracticeSession,
    kind: WordGapKind
  ) -> [WordGap] {
    pairs.compactMap { pair -> WordGap? in
      guard isPracticeWord(pair.word),
        let delta = validDelta(pair, reference: reference, attempt: attempt, kind: kind)
      else { return nil }
      return WordGap(pair: pair, delta: delta)
    }
  }

  /// A phrase-level claim needs several eligible words spread across the matched phrase.
  private static func repeatedPattern(
    in gaps: [WordGap], matchedWordCount: Int, threshold: Double
  ) -> [WordGap]? {
    let strong = gaps.filter { abs($0.delta) >= threshold }
    guard strong.count >= 3, strong.count * 2 >= gaps.count,
      let first = strong.first, let last = strong.last
    else { return nil }
    let spread = Double(last.pair.referenceIndex - first.pair.referenceIndex)
      / Double(max(1, matchedWordCount - 1))
    return spread >= 0.4 ? strong : nil
  }

  private static func patternExampleText(_ gaps: [WordGap], unit: String) -> String {
    gaps.map { gap in
      "“\(gap.pair.word)” was \(number(abs(gap.delta), 1)) \(unit) \(gap.delta < 0 ? "below" : "above") the reference"
    }.joined(separator: "; ")
  }

  private static func patternProgress(
    _ pattern: [WordGap], previous: PracticeSession?, previousComparison: MimicComparison?,
    reference: PracticeSession, kind: WordGapKind, unit: String, tolerance: Double
  ) -> String? {
    guard let previous, let previousComparison else { return nil }
    let priorByIndex = Dictionary(
      uniqueKeysWithValues: previousComparison.pairs.map { ($0.referenceIndex, $0) })
    let matched = pattern.compactMap { current -> (Double, Double)? in
      guard let pair = priorByIndex[current.pair.referenceIndex],
        let priorDelta = validDelta(pair, reference: reference, attempt: previous, kind: kind)
      else { return nil }
      return (abs(priorDelta), abs(current.delta))
    }
    guard matched.count >= 2, matched.count * 2 >= pattern.count else { return nil }
    let priorGap = median(matched.map(\.0))
    let currentGap = median(matched.map(\.1))
    let trend: String
    if priorGap - currentGap >= tolerance {
      trend = "Closer than the previous attempt"
    } else if currentGap - priorGap >= tolerance {
      trend = "Farther from the reference than the previous attempt"
    } else {
      trend = "Similar to the previous attempt"
    }
    return "\(trend): median gap across \(matched.count) words \(number(priorGap, 1)) → \(number(currentGap, 1)) \(unit)."
  }

  private static func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2)
      ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
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

  private struct TimingSummary {
    let driftMs: Double
    let referenceSpanMs: Double
    let largestSlipWord: String?
    let largestVariationWord: String?
    let largeTransitionCount: Int
    let largeTransitionSpread: Double
    let referenceIndices: [Int]
  }

  private static func timingSummary(_ pairs: [MimicWordPair]) -> TimingSummary? {
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
    let largeTransitions = offsets.indices.dropFirst().filter {
      abs(offsets[$0] - offsets[$0 - 1]) >= 180
    }
    let largestVariation = offsets.indices.dropFirst().max {
      abs(offsets[$0] - offsets[$0 - 1]) < abs(offsets[$1] - offsets[$1 - 1])
    }
    let spread = largeTransitions.first.flatMap { first in
      largeTransitions.last.map { Double($0 - first) / Double(max(1, pairs.count - 1)) }
    } ?? 0
    return TimingSummary(
      driftMs: drift, referenceSpanMs: referenceSpan,
      largestSlipWord: slipWord,
      largestVariationWord: largestVariation.map { pairs[$0].word },
      largeTransitionCount: largeTransitions.count, largeTransitionSpread: spread,
      referenceIndices: pairs.map(\.referenceIndex))
  }

  private static func unevenTimingProgress(
    current: TimingSummary, previous: MimicComparison?
  ) -> String? {
    guard let previous, previous.pairs.map(\.referenceIndex) == current.referenceIndices,
      let priorTiming = timingSummary(previous.pairs)
    else { return nil }
    return "Previous attempt: \(priorTiming.largeTransitionCount) large timing transitions; now \(current.largeTransitionCount)."
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
