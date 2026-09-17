import Foundation

public struct MimicWordPair: Sendable, Equatable {
    public let referenceIndex: Int
    public let attemptIndex: Int
    public let word: String
    public let reference: TranscriptWord
    public let attempt: TranscriptWord
    public let referencePitch: Double?
    public let attemptPitch: Double?
    public let referenceEnergy: Double?
    public let attemptEnergy: Double?

    public var durationDifferenceMs: Double {
        ((attempt.end - attempt.start) - (reference.end - reference.start)) * 1_000
    }
}

public struct MimicObservation: Sendable, Equatable {
    public let text: String
    public let referenceRange: ClosedRange<Double>
    public let attemptRange: ClosedRange<Double>

    public init(text: String, referenceRange: ClosedRange<Double>, attemptRange: ClosedRange<Double>) {
        self.text = text
        self.referenceRange = referenceRange
        self.attemptRange = attemptRange
    }
}

public struct MimicComparison: Sendable, Equatable {
    public let pairs: [MimicWordPair]
    public let correspondenceReliable: Bool
    public let observation: MimicObservation?

    public static func compare(reference: PracticeSession, attempt: PracticeSession) -> Self {
        guard let referenceWords = reference.transcription?.words,
              let attemptWords = attempt.transcription?.words,
              !referenceWords.isEmpty, !attemptWords.isEmpty,
              referenceWords.count <= 160, attemptWords.count <= 160
        else { return .init(pairs: [], correspondenceReliable: false, observation: nil) }

        let left = referenceWords.map { normalized($0.word) }
        let right = attemptWords.map { normalized($0.word) }
        var lengths = Array(repeating: Array(repeating: 0, count: right.count + 1), count: left.count + 1)
        for i in 1...left.count {
            for j in 1...right.count {
                if !left[i - 1].isEmpty && left[i - 1] == right[j - 1] {
                    lengths[i][j] = lengths[i - 1][j - 1] + 1
                } else {
                    lengths[i][j] = max(lengths[i - 1][j], lengths[i][j - 1])
                }
            }
        }
        var indices: [(Int, Int)] = []
        var i = left.count
        var j = right.count
        while i > 0 && j > 0 {
            if !left[i - 1].isEmpty && left[i - 1] == right[j - 1] {
                indices.append((i - 1, j - 1))
                i -= 1
                j -= 1
            } else if lengths[i - 1][j] >= lengths[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        indices.reverse()
        let reliable = indices.count >= 2 && Double(indices.count) / Double(max(left.count, right.count)) >= 0.75
        let pairs = indices.map { a, b in
            MimicWordPair(
                referenceIndex: a, attemptIndex: b, word: referenceWords[a].word,
                reference: referenceWords[a], attempt: attemptWords[b],
                referencePitch: reference.words.indices.contains(a) ? reference.words[a].pitch.relativeMedianSemitones : nil,
                attemptPitch: attempt.words.indices.contains(b) ? attempt.words[b].pitch.relativeMedianSemitones : nil,
                referenceEnergy: reference.words.indices.contains(a) ? reference.words[a].loudness.relativeMeanDB : nil,
                attemptEnergy: attempt.words.indices.contains(b) ? attempt.words[b].loudness.relativeMeanDB : nil
            )
        }
        guard reliable, attempt.result.metrics.clippingPercent < 3,
              reference.result.metrics.clippingPercent < 3,
              attempt.result.metrics.snrDB >= 6,
              reference.result.metrics.snrDB >= 6
        else { return .init(pairs: pairs, correspondenceReliable: false, observation: nil) }

        // Only matched adjacent words support a specific pause comparison.
        var largestPause: (difference: Double, observation: MimicObservation)?
        for (previous, next) in zip(pairs, pairs.dropFirst()) {
            guard next.referenceIndex == previous.referenceIndex + 1,
                  next.attemptIndex == previous.attemptIndex + 1 else { continue }
            let refGap = max(0, next.reference.start - previous.reference.end)
            let ownGap = max(0, next.attempt.start - previous.attempt.end)
            let difference = ownGap - refGap
            guard abs(difference) >= 0.12 else { continue }
            let qualifier = difference > 0 ? "longer" : "shorter"
            let text = "Your pause before “\(next.word)” was \(Int((abs(difference) * 1_000).rounded())) ms \(qualifier)."
            let observation = MimicObservation(
                text: text,
                referenceRange: previous.reference.start...next.reference.end,
                attemptRange: previous.attempt.start...next.attempt.end
            )
            if abs(difference) > abs(largestPause?.difference ?? 0) {
                largestPause = (difference, observation)
            }
        }
        if let largestPause {
            return .init(pairs: pairs, correspondenceReliable: true, observation: largestPause.observation)
        }

        if let mostDifferent = pairs.max(by: { abs($0.durationDifferenceMs) < abs($1.durationDifferenceMs) }),
           abs(mostDifferent.durationDifferenceMs) >= 130 {
            let qualifier = mostDifferent.durationDifferenceMs > 0 ? "longer" : "shorter"
            return .init(
                pairs: pairs, correspondenceReliable: true,
                observation: MimicObservation(
                    text: "Your “\(mostDifferent.word)” was \(Int(abs(mostDifferent.durationDifferenceMs).rounded())) ms \(qualifier).",
                    referenceRange: mostDifferent.reference.start...mostDifferent.reference.end,
                    attemptRange: mostDifferent.attempt.start...mostDifferent.attempt.end
                )
            )
        }
        return .init(pairs: pairs, correspondenceReliable: true, observation: nil)
    }

    private static func normalized(_ word: String) -> String {
        word.lowercased().unicodeScalars
            .filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
            .map(String.init).joined()
    }
}
