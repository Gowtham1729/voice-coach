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
}

public struct MimicComparison: Sendable, Equatable {
    public let pairs: [MimicWordPair]
    public let correspondenceReliable: Bool

    public static func compare(reference: PracticeSession, attempt: PracticeSession) -> Self {
        guard let referenceWords = reference.transcription?.words,
              let attemptWords = attempt.transcription?.words,
              !referenceWords.isEmpty, !attemptWords.isEmpty,
              referenceWords.count <= 160, attemptWords.count <= 160
        else { return .init(pairs: [], correspondenceReliable: false) }

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
        let correspondenceReliable = reliable
            && attempt.result.metrics.clippingPercent < 3
            && reference.result.metrics.clippingPercent < 3
            && attempt.result.metrics.snrDB >= 6
            && reference.result.metrics.snrDB >= 6
        return .init(pairs: pairs, correspondenceReliable: correspondenceReliable)
    }

    private static func normalized(_ word: String) -> String {
        word.lowercased().unicodeScalars
            .filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
            .map(String.init).joined()
    }
}
