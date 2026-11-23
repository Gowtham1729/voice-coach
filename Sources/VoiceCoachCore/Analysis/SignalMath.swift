import Foundation

func rootMeanSquare<Samples: Collection>(_ samples: Samples) -> Double
where Samples.Element == Float {
  guard !samples.isEmpty else { return 0 }
  return sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count))
}

/// Loudness above which a frame counts as speech. Analysis, word metrics, and the
/// report must agree on this, so it lives in one place.
func activeSpeechThreshold(noiseFloorDBFS: Double) -> Double {
  min(-32, max(-50, noiseFloorDBFS + 8))
}

func amplitudeToDB(_ amplitude: Double) -> Double {
  max(-80, 20 * log10(max(amplitude, 0.0001)))
}

func mean(_ values: [Double]) -> Double {
  values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
}

func median(_ values: [Double]) -> Double {
  percentile(values, 0.5)
}

func percentile(_ values: [Double], _ percentile: Double) -> Double {
  guard !values.isEmpty else { return 0 }
  let sorted = values.sorted()
  let position = max(0, min(1, percentile)) * Double(sorted.count - 1)
  let lower = Int(floor(position))
  let upper = Int(ceil(position))
  guard lower != upper else { return sorted[lower] }
  let fraction = position - Double(lower)
  return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
}

func standardDeviation(_ values: [Double]) -> Double {
  let average = mean(values)
  return sqrt(mean(values.map { pow($0 - average, 2) }))
}

/// Mean frame-to-frame change as a percentage of the mean value. Only points closer
/// than `maximumGap` seconds are compared, so a jump across a pause or an unvoiced
/// stretch does not count as frame-level instability.
func relativeSuccessiveDifference(_ points: [TimePoint], maximumGap: Double) -> Double? {
  let differences = zip(points, points.dropFirst()).compactMap { previous, next in
    next.time - previous.time <= maximumGap ? abs(next.value - previous.value) : nil
  }
  let average = mean(points.map(\.value))
  guard !differences.isEmpty, average > 0 else { return nil }
  return mean(differences) / average * 100
}

func semitoneDistance(low: Double?, high: Double?) -> Double? {
  guard let low, let high, low > 0, high > 0 else { return nil }
  return 12 * log2(high / low)
}

func optionalStatistic(_ values: [Double], _ operation: ([Double]) -> Double) -> Double? {
  values.isEmpty ? nil : operation(values)
}
