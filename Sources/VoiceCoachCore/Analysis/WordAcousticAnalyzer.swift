import Foundation

public struct WordAcousticAnalyzer: Sendable {
  /// Thresholds for word median pitch calculation.
  public let minimumPitchFramesMedian: Int
  public let minimumPitchCoverageMedian: Double

  /// Thresholds for word pitch range (P10–P90) calculation.
  public let minimumPitchFramesRange: Int
  public let minimumPitchCoverageRange: Double

  /// Thresholds for word start-to-end movement calculation.
  public let minimumPitchFramesStartToEnd: Int
  public let minimumPitchCoverageStartToEnd: Double
  public let minimumEdgeFramesStartToEnd: Int

  public init(
    minimumPitchFramesMedian: Int = 4,
    minimumPitchCoverageMedian: Double = 0.25,
    minimumPitchFramesRange: Int = 8,
    minimumPitchCoverageRange: Double = 0.45,
    minimumPitchFramesStartToEnd: Int = 10,
    minimumPitchCoverageStartToEnd: Double = 0.50,
    minimumEdgeFramesStartToEnd: Int = 3
  ) {
    self.minimumPitchFramesMedian = max(2, minimumPitchFramesMedian)
    self.minimumPitchCoverageMedian = max(0.0, min(1.0, minimumPitchCoverageMedian))
    self.minimumPitchFramesRange = max(4, minimumPitchFramesRange)
    self.minimumPitchCoverageRange = max(0.0, min(1.0, minimumPitchCoverageRange))
    self.minimumPitchFramesStartToEnd = max(6, minimumPitchFramesStartToEnd)
    self.minimumPitchCoverageStartToEnd = max(0.0, min(1.0, minimumPitchCoverageStartToEnd))
    self.minimumEdgeFramesStartToEnd = max(2, minimumEdgeFramesStartToEnd)
  }

  public func analyze(
    transcription: TranscriptionResult,
    result: AnalysisResult
  ) -> [WordAnalysis] {
    let activeThreshold = activeSpeechThreshold(noiseFloorDBFS: result.metrics.noiseFloorDBFS)
    return transcription.words.map { word in
      let loudnessPoints = frames(
        from: word.start, to: word.end, in: result.acousticFrames.loudness)
      let totalAcousticFrames = loudnessPoints.count

      let pitchPoints = frames(from: word.start, to: word.end, in: result.acousticFrames.pitch)
        .filter { $0.value.isFinite && $0.value > 0 }

      let activeLoudnessPoints = loudnessPoints.filter {
        $0.value.isFinite && $0.value >= activeThreshold
      }

      return WordAnalysis(
        word: word.word,
        start: word.start,
        end: word.end,
        pitch: pitchMetrics(
          pitchPoints: pitchPoints,
          totalFrames: totalAcousticFrames,
          recordingMedian: result.metrics.medianPitchHz
        ),
        loudness: loudnessMetrics(
          activePoints: activeLoudnessPoints,
          totalFrames: totalAcousticFrames,
          activeSpeechMean: result.metrics.meanLoudnessDBFS
        )
      )
    }
  }

  private func pitchMetrics(
    pitchPoints: [TimePoint],
    totalFrames: Int,
    recordingMedian: Double?
  ) -> WordPitchMetrics {
    let validPitchFrames = pitchPoints.count
    let pitchCoverage = totalFrames > 0 ? Double(validPitchFrames) / Double(totalFrames) : 0.0

    let pitchValues = pitchPoints.map(\.value)

    // 1. Median & relative median pitch: requires moderate evidence
    let wordMedian: Double?
    let relativeMedian: Double?
    if validPitchFrames >= minimumPitchFramesMedian && pitchCoverage >= minimumPitchCoverageMedian {
      let med = median(pitchValues)
      wordMedian = med
      relativeMedian = recordingMedian.flatMap { reference -> Double? in
        guard reference.isFinite, reference > 0, med > 0 else { return nil }
        return 12 * log2(med / reference)
      }
    } else {
      wordMedian = nil
      relativeMedian = nil
    }

    // 2. Pitch range: requires stronger evidence (coverage >= 0.45, valid frames >= 8)
    let range: Double?
    if validPitchFrames >= minimumPitchFramesRange && pitchCoverage >= minimumPitchCoverageRange {
      let p10 = percentile(pitchValues, 0.10)
      let p90 = percentile(pitchValues, 0.90)
      range = semitoneDifference(from: p10, to: p90)
    } else {
      range = nil
    }

    // 3. Start-to-end movement: requires strongest evidence (coverage >= 0.50, valid frames >= 10,
    // and at least 3 valid frames in both early and late portions separated by at least 50 ms)
    let movement = startToEndMovement(
      pitchPoints: pitchPoints,
      validPitchFrames: validPitchFrames,
      pitchCoverage: pitchCoverage
    )

    return WordPitchMetrics(
      medianHz: wordMedian,
      relativeMedianSemitones: relativeMedian,
      rangeSemitones: range,
      startToEndSemitones: movement,
      validPitchFrames: validPitchFrames,
      pitchCoverage: pitchCoverage
    )
  }

  private func startToEndMovement(
    pitchPoints: [TimePoint],
    validPitchFrames: Int,
    pitchCoverage: Double
  ) -> Double? {
    guard validPitchFrames >= minimumPitchFramesStartToEnd,
      pitchCoverage >= minimumPitchCoverageStartToEnd,
      let firstTime = pitchPoints.first?.time,
      let lastTime = pitchPoints.last?.time
    else {
      return nil
    }

    let voicedDuration = lastTime - firstTime
    guard voicedDuration >= 0.08 else { return nil }

    let earlyThreshold = firstTime + 0.35 * voicedDuration
    let lateThreshold = lastTime - 0.35 * voicedDuration
    let earlyFrames = pitchPoints.filter { $0.time <= earlyThreshold }
    let lateFrames = pitchPoints.filter { $0.time >= lateThreshold }

    guard earlyFrames.count >= minimumEdgeFramesStartToEnd,
      lateFrames.count >= minimumEdgeFramesStartToEnd
    else {
      return nil
    }

    let earlyMedianTime = median(earlyFrames.map(\.time))
    let lateMedianTime = median(lateFrames.map(\.time))
    guard lateMedianTime - earlyMedianTime >= 0.05 else { return nil }

    let startMedian = median(earlyFrames.map(\.value))
    let endMedian = median(lateFrames.map(\.value))
    return semitoneDifference(from: startMedian, to: endMedian)
  }

  private func loudnessMetrics(
    activePoints: [TimePoint],
    totalFrames: Int,
    activeSpeechMean: Double
  ) -> WordLoudnessMetrics {
    let activeFrameCoverage =
      totalFrames > 0 ? Double(activePoints.count) / Double(totalFrames) : 0.0

    guard !activePoints.isEmpty else {
      return WordLoudnessMetrics(
        relativeMeanDB: nil,
        startToEndDB: nil,
        activeFrameCoverage: activeFrameCoverage
      )
    }

    let activeDB = activePoints.map(\.value)
    let relativeMean = activeSpeechMean.isFinite ? mean(activeDB) - activeSpeechMean : nil
    let movement = loudnessMovement(activePoints: activePoints)

    return WordLoudnessMetrics(
      relativeMeanDB: relativeMean,
      startToEndDB: movement,
      activeFrameCoverage: activeFrameCoverage
    )
  }

  private func loudnessMovement(activePoints: [TimePoint]) -> Double? {
    guard activePoints.count >= 4,
      let firstTime = activePoints.first?.time,
      let lastTime = activePoints.last?.time
    else {
      return nil
    }

    let span = lastTime - firstTime
    guard span >= 0.04 else { return nil }

    let earlyThreshold = firstTime + 0.35 * span
    let lateThreshold = lastTime - 0.35 * span
    let earlyFrames = activePoints.filter { $0.time <= earlyThreshold }
    let lateFrames = activePoints.filter { $0.time >= lateThreshold }

    guard earlyFrames.count >= 2, lateFrames.count >= 2 else { return nil }

    let startMedian = median(earlyFrames.map(\.value))
    let endMedian = median(lateFrames.map(\.value))
    return endMedian - startMedian
  }

  /// Takes plain bounds rather than a `ClosedRange`, which would trap on a word whose
  /// end precedes its start before this guard could reject it.
  private func frames(from start: Double, to end: Double, in points: [TimePoint]) -> [TimePoint] {
    guard start.isFinite, end.isFinite, end >= start else { return [] }
    return points.filter { $0.time >= start && $0.time <= end }
  }

  private func semitoneDifference(from low: Double?, to high: Double?) -> Double? {
    guard let low, let high, low.isFinite, high.isFinite, low > 0, high > 0 else { return nil }
    return 12 * log2(high / low)
  }
}
