import Foundation

public enum ReportFormatter {
    public static func makeReport(session: PracticeSession) -> String {
        let result = session.result
        let value = result.metrics
        let pitchContour = normalizedContour(
            result.pitchContour,
            count: 12,
            reference: value.medianPitchHz,
            transform: { frequency, median in 12 * log2(frequency / median) }
        )
        let activeLoudness = result.loudnessContour.filter {
            $0.value >= min(-32, max(-50, value.noiseFloorDBFS + 8))
        }
        let loudnessContour = normalizedContour(
            activeLoudness,
            count: 12,
            reference: value.meanLoudnessDBFS,
            transform: { loudness, mean in loudness - mean }
        )

        let report: [String: Any] = [
            "recording": [
                "duration_s": rounded(value.duration, 2),
                "active_speech_s": rounded(value.activeSpeechDuration, 2),
                "sample_rate_hz": rounded(value.sampleRateHz, 0)
            ],
            "recording_quality": [
                "noise_floor_dbfs": rounded(value.noiseFloorDBFS, 2),
                "snr_db": rounded(value.snrDB, 2),
                "clipping_pct": rounded(value.clippingPercent, 2)
            ],
            "pitch": [
                "median_hz": json(value.medianPitchHz, places: 2),
                "p05_hz": json(value.pitchLowHz, places: 2),
                "p95_hz": json(value.pitchHighHz, places: 2),
                "range_hz": json(difference(value.pitchHighHz, value.pitchLowHz), places: 2),
                "range_semitones": json(value.pitchRangeSemitones, places: 2),
                "std_hz": json(value.pitchVariationHz, places: 2),
                "std_semitones": json(value.pitchStandardDeviationSemitones, places: 2),
                "frame_instability_pct": json(value.pitchInstabilityPercent, places: 2),
                "contour_semitones": pitchContour
            ],
            "loudness": [
                "active_mean_dbfs": rounded(value.meanLoudnessDBFS, 2),
                "p10_p90_range_db": rounded(value.loudnessDynamicRangeDB, 2),
                "std_db": rounded(value.loudnessStandardDeviationDB, 2),
                "start_dbfs": rounded(value.phraseStartDBFS, 2),
                "end_dbfs": rounded(value.phraseEndDBFS, 2),
                "end_minus_start_db": rounded(value.phraseDecayDB, 2),
                "contour_relative_db": loudnessContour
            ],
            "pauses": [
                "pause_ratio": rounded(value.pauseRatio, 2),
                "pause_count": value.pauseCount,
                "mean_pause_ms": rounded(value.meanPauseMs, 0),
                "median_pause_ms": rounded(value.medianPauseMs, 0),
                "longest_pause_ms": rounded(value.longestPauseMs, 0)
            ],
            "voice_quality": [
                "hnr_db": json(value.hnrDB, places: 2),
                "cpp_db": json(value.cppDB, places: 2)
            ]
        ]

        guard JSONSerialization.isValidJSONObject(report),
              let data = try? JSONSerialization.data(
                withJSONObject: report,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              )
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func normalizedContour(
        _ points: [TimePoint],
        count: Int,
        reference: Double?,
        transform: (Double, Double) -> Double
    ) -> [Decimal] {
        guard !points.isEmpty, let reference, reference != 0 else { return [] }
        let bucketCount = min(count, points.count)
        return (0..<bucketCount).map { bucket in
            let start = bucket * points.count / bucketCount
            let end = max(start + 1, (bucket + 1) * points.count / bucketCount)
            let representative = median(points[start..<min(end, points.count)].map(\.value))
            return rounded(transform(representative, reference), 2)
        }
    }

    private static func difference(_ high: Double?, _ low: Double?) -> Double? {
        guard let high, let low else { return nil }
        return high - low
    }

    private static func json(_ value: Double?, places: Int = 2) -> Any {
        guard let value, value.isFinite else { return NSNull() }
        return rounded(value, places)
    }

    private static func rounded(_ value: Double, _ places: Int = 2) -> Decimal {
        guard value.isFinite else { return Decimal(0) }
        var decimal = Decimal(value)
        var result = Decimal()
        NSDecimalRound(&result, &decimal, places, .plain)
        if result.isZero {
            return Decimal(0)
        }
        return result
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
