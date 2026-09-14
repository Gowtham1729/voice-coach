import Foundation

public struct WordAcousticAnalyzer: Sendable {
    /// Three reliable voiced frames is the minimum for a word-level pitch summary.
    /// At the analyzer's usual hop size this is roughly 60 ms of voiced evidence.
    public let minimumPitchFrames: Int

    public init(minimumPitchFrames: Int = 3) {
        self.minimumPitchFrames = max(2, minimumPitchFrames)
    }

    public func analyze(
        transcription: TranscriptionResult,
        result: AnalysisResult
    ) -> [WordAnalysis] {
        transcription.words.map { word in
            let pitchFrames = frames(in: word.start...word.end, from: result.acousticFrames.pitch)
                .map(\.value)
                .filter { $0.isFinite && $0 > 0 }
            let loudnessFrames = frames(in: word.start...word.end, from: result.acousticFrames.loudness)
                .map(\.value)
                .filter(\.isFinite)

            return WordAnalysis(
                word: word.word,
                start: word.start,
                end: word.end,
                pitch: pitchMetrics(
                    frames: pitchFrames,
                    recordingMedian: result.metrics.medianPitchHz
                ),
                loudness: loudnessMetrics(
                    frames: loudnessFrames,
                    activeSpeechMean: result.metrics.meanLoudnessDBFS
                )
            )
        }
    }

    private func pitchMetrics(
        frames: [Double],
        recordingMedian: Double?
    ) -> WordPitchMetrics {
        guard frames.count >= minimumPitchFrames else {
            return WordPitchMetrics(
                medianHz: nil,
                relativeMedianSemitones: nil,
                rangeSemitones: nil,
                startToEndSemitones: nil
            )
        }

        let wordMedian = median(frames)
        let relativeMedian = recordingMedian.flatMap { reference -> Double? in
            guard reference.isFinite, reference > 0, wordMedian > 0 else { return nil }
            return 12 * log2(wordMedian / reference)
        }
        let low = frames.min()
        let high = frames.max()
        let range = semitoneDifference(from: low, to: high)

        // Use medians from the leading and trailing thirds. This is robust to a
        // single edge frame and uses measured frames only—there is no interpolation.
        let edgeCount = max(1, frames.count / 3)
        let movement = frames.count >= max(4, minimumPitchFrames)
            ? semitoneDifference(
                from: median(Array(frames.prefix(edgeCount))),
                to: median(Array(frames.suffix(edgeCount)))
            )
            : nil

        return WordPitchMetrics(
            medianHz: wordMedian,
            relativeMedianSemitones: relativeMedian,
            rangeSemitones: range,
            startToEndSemitones: movement
        )
    }

    private func loudnessMetrics(
        frames: [Double],
        activeSpeechMean: Double
    ) -> WordLoudnessMetrics {
        guard !frames.isEmpty else {
            return WordLoudnessMetrics(relativeMeanDB: nil, startToEndDB: nil)
        }
        let relativeMean = activeSpeechMean.isFinite ? mean(frames) - activeSpeechMean : nil
        let edgeCount = max(1, frames.count / 3)
        let movement = frames.count >= 2
            ? median(Array(frames.suffix(edgeCount))) - median(Array(frames.prefix(edgeCount)))
            : nil
        return WordLoudnessMetrics(relativeMeanDB: relativeMean, startToEndDB: movement)
    }

    private func frames(in range: ClosedRange<Double>, from points: [TimePoint]) -> [TimePoint] {
        guard range.lowerBound.isFinite,
              range.upperBound.isFinite,
              range.upperBound >= range.lowerBound
        else { return [] }
        return points.filter { range.contains($0.time) }
    }

    private func semitoneDifference(from low: Double?, to high: Double?) -> Double? {
        guard let low, let high, low.isFinite, high.isFinite, low > 0, high > 0 else { return nil }
        return 12 * log2(high / low)
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    private func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
