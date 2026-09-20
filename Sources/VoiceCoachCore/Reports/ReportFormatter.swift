import Foundation

public enum ReportFormatter {
  /// The original compact V1 report: recording-level acoustic data only.
  /// This intentionally excludes transcription and all word-level payloads.
  public static func makeCompactReport(session: PracticeSession) -> String {
    encode(compactObject(session: session))
  }

  /// Dual-take Mimic clipboard payload: compact reports, transcripts, and alignment deltas.
  /// Omits per-word `alignment.words` when correspondence is unreliable.
  public static func makeMimicCompareReport(
    reference: PracticeSession,
    attempt: PracticeSession,
    practiceStyle: String,
    comparison: MimicComparison? = nil
  ) -> String {
    let aligned = comparison ?? MimicComparison.compare(reference: reference, attempt: attempt)
    var alignment: [String: Any] = [
      "reliable": aligned.correspondenceReliable,
      "status": aligned.status.rawValue,
      "matched_word_count": aligned.pairs.count,
    ]
    if aligned.correspondenceReliable {
      alignment["words"] = aligned.pairs.map(alignmentWordRow)
    }

    return encode([
      "schema_version": 1,
      "practice_style": practiceStyle,
      "reference": compactObject(session: reference),
      "attempt": compactObject(session: attempt),
      "reference_transcript": reference.transcription?.text ?? NSNull(),
      "attempt_transcript": attempt.transcription?.text ?? NSNull(),
      "alignment": alignment,
    ])
  }

  public static func makeReport(session: PracticeSession) -> String {
    let result = session.result
    let value = result.metrics
    let transcriptionText: Any
    if let text = session.transcription?.text {
      transcriptionText = text
    } else {
      transcriptionText = NSNull()
    }
    let pitchContour = normalizedContour(
      result.pitchContour,
      count: 24,
      reference: value.medianPitchHz,
      transform: { frequency, median in 12 * log2(frequency / median) }
    )
    let activeLoudness = result.loudnessContour.filter {
      $0.value >= min(-32, max(-50, value.noiseFloorDBFS + 8))
    }
    let loudnessContour = normalizedContour(
      activeLoudness,
      count: 24,
      reference: value.meanLoudnessDBFS,
      transform: { loudness, mean in loudness - mean }
    )

    let report: [String: Any] = [
      "recording": [
        "duration_s": rounded(value.duration, 2),
        "active_speech_s": rounded(value.activeSpeechDuration, 2),
        "sample_rate_hz": rounded(value.sampleRateHz, 0),
      ],
      "recording_quality": [
        "noise_floor_dbfs": rounded(value.noiseFloorDBFS, 2),
        "snr_db": rounded(value.snrDB, 2),
        "clipping_pct": rounded(value.clippingPercent, 2),
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
        "contour_semitones": pitchContour,
      ],
      "loudness": [
        "active_mean_dbfs": rounded(value.meanLoudnessDBFS, 2),
        "p10_p90_range_db": rounded(value.loudnessDynamicRangeDB, 2),
        "std_db": rounded(value.loudnessStandardDeviationDB, 2),
        "start_dbfs": rounded(value.phraseStartDBFS, 2),
        "end_dbfs": rounded(value.phraseEndDBFS, 2),
        "end_minus_start_db": rounded(value.phraseDecayDB, 2),
        "contour_relative_db": loudnessContour,
      ],
      "pauses": [
        "non_speech_ratio": rounded(value.nonSpeechRatio, 2),
        "internal_pause_count": value.internalPauseCount,
        "internal_pause_total_ms": rounded(value.internalPauseTotalMs, 0),
        "mean_internal_pause_ms": rounded(value.meanInternalPauseMs, 0),
        "median_internal_pause_ms": rounded(value.medianInternalPauseMs, 0),
        "longest_internal_pause_ms": rounded(value.longestInternalPauseMs, 0),
        "leading_silence_ms": rounded(value.leadingSilenceMs, 0),
        "trailing_silence_ms": rounded(value.trailingSilenceMs, 0),
      ],
      "voice_quality": [
        "hnr_db": json(value.hnrDB, places: 2)
      ],
      "transcription": [
        "text": transcriptionText
      ],
      "words": session.words.map { word in
        [
          "word": word.word,
          "start_s": rounded(word.start, 2),
          "end_s": rounded(word.end, 2),
          "duration_ms": rounded(max(0, word.end - word.start) * 1_000, 0),
          "pitch": [
            "median_hz": json(word.pitch.medianHz, places: 1),
            "relative_median_semitones": json(word.pitch.relativeMedianSemitones, places: 2),
            "range_semitones": json(word.pitch.rangeSemitones, places: 2),
            "start_to_end_semitones": json(word.pitch.startToEndSemitones, places: 2),
            "valid_pitch_frames": word.pitch.validPitchFrames,
            "pitch_coverage": rounded(word.pitch.pitchCoverage, 2),
          ],
          "loudness": [
            "relative_mean_db": json(word.loudness.relativeMeanDB, places: 2),
            "start_to_end_db": json(word.loudness.startToEndDB, places: 2),
            "active_frame_coverage": rounded(word.loudness.activeFrameCoverage, 2),
          ],
        ] as [String: Any]
      },
    ]

    return encode(report)
  }

  /// Generates an aligned frame-by-frame timeline inspection string for debugging acoustic analysis,
  /// showing time, RMS loudness, VAD activation, pitch estimation, and ASR word boundaries.
  public static func makeTimelineDebug(session: PracticeSession) -> String {
    let activeThreshold = min(-32, max(-50, session.result.metrics.noiseFloorDBFS + 8))
    var lines: [String] = []
    lines.append(
      String(
        format: "%-10@ | %-12@ | %-8@ | %-12@ | %@", "Time (s)", "Loudness", "VAD", "Pitch (Hz)",
        "ASR Word"))
    lines.append(String(repeating: "-", count: 64))

    let pitchPoints = session.result.acousticFrames.pitch
    var pitchIndex = 0

    for frame in session.result.acousticFrames.loudness {
      let t = frame.time
      let db = frame.value
      let vad = db >= activeThreshold ? "ACTIVE" : "SILENCE"

      while pitchIndex < pitchPoints.count && pitchPoints[pitchIndex].time < t - 0.006 {
        pitchIndex += 1
      }
      let pitchStr: String
      if pitchIndex < pitchPoints.count && abs(pitchPoints[pitchIndex].time - t) <= 0.006 {
        pitchStr = String(format: "%6.1f Hz", pitchPoints[pitchIndex].value)
      } else {
        pitchStr = "    ----   "
      }

      let word = session.words.first(where: { $0.start <= t && t <= $0.end })?.word ?? ""

      lines.append(
        String(format: "%10.3f | %8.2f dBFS | %-8@ | %@ | %@", t, db, vad, pitchStr, word))
    }

    return lines.joined(separator: "\n")
  }

  private static func alignmentWordRow(_ pair: MimicWordPair) -> [String: Any] {
    let refDurationMs = max(0, pair.reference.end - pair.reference.start) * 1_000
    let attemptDurationMs = max(0, pair.attempt.end - pair.attempt.start) * 1_000
    return [
      "word": pair.word,
      "ref_start_s": rounded(pair.reference.start, 2),
      "attempt_start_s": rounded(pair.attempt.start, 2),
      "ref_duration_ms": rounded(refDurationMs, 0),
      "attempt_duration_ms": rounded(attemptDurationMs, 0),
      "duration_delta_ms": rounded(attemptDurationMs - refDurationMs, 0),
      "start_delta_ms": rounded((pair.attempt.start - pair.reference.start) * 1_000, 0),
      "ref_pitch_st": json(pair.referencePitch, places: 2),
      "attempt_pitch_st": json(pair.attemptPitch, places: 2),
      "pitch_delta_st": json(difference(pair.attemptPitch, pair.referencePitch), places: 2),
      "ref_energy_db": json(pair.referenceEnergy, places: 2),
      "attempt_energy_db": json(pair.attemptEnergy, places: 2),
      "energy_delta_db": json(difference(pair.attemptEnergy, pair.referenceEnergy), places: 2),
    ]
  }

  private static func compactObject(session: PracticeSession) -> [String: Any] {
    let fullReport = makeReport(session: session)
    guard let data = fullReport.data(using: .utf8),
      var report = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return [:] }
    report.removeValue(forKey: "transcription")
    report.removeValue(forKey: "words")
    return report
  }

  private static func encode(_ report: [String: Any]) -> String {
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
    if points.count >= count {
      return (0..<count).map { bucket in
        let start = bucket * points.count / count
        let end = max(start + 1, (bucket + 1) * points.count / count)
        let representative = median(points[start..<min(end, points.count)].map(\.value))
        return rounded(transform(representative, reference), 2)
      }
    } else {
      return (0..<count).map { bucket in
        let index = bucket * (points.count - 1) / max(1, count - 1)
        let representative = points[index].value
        return rounded(transform(representative, reference), 2)
      }
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
