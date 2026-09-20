import Foundation

extension AudioAnalyzer {
  func cppSummary(samples: [Float], sampleRate: Double) -> Double? {
    let fftSize = min(1024, samples.count)
    guard fftSize >= 128 else { return nil }
    let windowCount = min(12, max(1, samples.count / fftSize))
    var values: [Double] = []

    for windowIndex in 0..<windowCount {
      let center = Int(Double(windowIndex + 1) / Double(windowCount + 1) * Double(samples.count))
      let start = max(0, min(samples.count - fftSize, center - fftSize / 2))
      let frame = Array(samples[start..<(start + fftSize)])
      guard amplitudeToDB(rootMeanSquare(frame)) > -50 else { continue }
      if let cpp = cepstralPeakProminence(frame: frame, sampleRate: sampleRate) {
        values.append(cpp)
      }
    }
    return values.isEmpty ? nil : median(values)
  }

  func cepstralPeakProminence(frame: [Float], sampleRate: Double) -> Double? {
    let n = frame.count
    guard n >= 128 else { return nil }
    let bins = n / 2 + 1
    var result = [Double](repeating: 0, count: bins)
    for bin in 0..<bins {
      var real = 0.0
      var imaginary = 0.0
      for index in 0..<n {
        let window = 0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(n - 1))
        let angle = -2 * .pi * Double(bin * index) / Double(n)
        let value = Double(frame[index]) * window
        real += value * cos(angle)
        imaginary += value * sin(angle)
      }
      result[bin] = 20 * log10(max(sqrt(real * real + imaginary * imaginary), 1e-9))
    }

    let minimumQuefrency = max(1, Int(sampleRate / 500))
    let maximumQuefrency = min(n / 2 - 1, Int(sampleRate / 70))
    guard maximumQuefrency > minimumQuefrency else { return nil }
    var cepstrum: [(x: Double, y: Double)] = []
    for quefrency in minimumQuefrency...maximumQuefrency {
      var sum = result[0]
      if bins > 2 {
        for bin in 1..<(bins - 1) {
          sum += 2 * result[bin] * cos(2 * .pi * Double(bin * quefrency) / Double(n))
        }
      }
      sum += result[bins - 1] * cos(.pi * Double(quefrency))
      cepstrum.append((Double(quefrency), sum / Double(n)))
    }

    guard let peak = cepstrum.max(by: { $0.y < $1.y }) else { return nil }
    let meanX = mean(cepstrum.map(\.x))
    let meanY = mean(cepstrum.map(\.y))
    let denominator = cepstrum.reduce(0.0) { $0 + pow($1.x - meanX, 2) }
    let slope =
      denominator > 0
      ? cepstrum.reduce(0.0) { $0 + ($1.x - meanX) * ($1.y - meanY) } / denominator
      : 0
    let baselineAtPeak = meanY + slope * (peak.x - meanX)
    return max(0, peak.y - baselineAtPeak)
  }

  func pauseDurations(
    loudness: [TimePoint],
    activeThreshold: Double,
    hopSize: Int,
    sampleRate: Double
  ) -> [Double] {
    let active = loudness.map { $0.value >= activeThreshold }
    guard let firstActive = active.firstIndex(of: true),
      let lastActive = active.lastIndex(of: true),
      firstActive < lastActive
    else { return [] }

    let minimumFrames = max(1, Int(ceil(0.15 * sampleRate / Double(hopSize))))
    var result: [Double] = []
    var run = 0
    for index in firstActive...lastActive {
      if active[index] {
        if run >= minimumFrames {
          result.append(Double(run * hopSize) / sampleRate)
        }
        run = 0
      } else {
        run += 1
      }
    }
    return result
  }

  func makeSpectrogram(samples: [Float], sampleRate: Double) -> SpectrogramData {
    let fftSize = min(256, samples.count)
    guard fftSize >= 64 else { return SpectrogramData(columns: 0, rows: 0, decibels: []) }
    let columns = min(180, max(1, samples.count / fftSize))
    let maximumFrequency = min(8_000.0, sampleRate / 2)
    let rows = max(1, min(96, Int(maximumFrequency / (sampleRate / Double(fftSize)))))
    var values: [Double] = []
    values.reserveCapacity(columns * rows)

    for column in 0..<columns {
      let fraction = columns == 1 ? 0.0 : Double(column) / Double(columns - 1)
      let start = min(samples.count - fftSize, Int(fraction * Double(samples.count - fftSize)))
      let frame = Array(samples[start..<(start + fftSize)])
      let magnitudes = magnitudeSpectrum(frame: frame, binCount: rows)
      values.append(contentsOf: magnitudes.map { max(-80, 20 * log10(max($0, 1e-8))) })
    }
    return SpectrogramData(columns: columns, rows: rows, decibels: values)
  }

  func magnitudeSpectrum(frame: [Float], binCount: Int) -> [Double] {
    let n = frame.count
    let bins = min(binCount, n / 2 + 1)
    guard n > 1 else { return [] }
    var result = [Double](repeating: 0, count: bins)
    for bin in 0..<bins {
      var real = 0.0
      var imaginary = 0.0
      for index in 0..<n {
        let window = 0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(n - 1))
        let angle = -2 * .pi * Double(bin * index) / Double(n)
        let value = Double(frame[index]) * window
        real += value * cos(angle)
        imaginary += value * sin(angle)
      }
      result[bin] = sqrt(real * real + imaginary * imaginary)
    }
    return result
  }

  func waveform(samples: [Float], bins: Int) -> [WaveformPoint] {
    let count = min(bins, samples.count)
    guard count > 0 else { return [] }
    return (0..<count).map { bin in
      let start = bin * samples.count / count
      let end = max(start + 1, (bin + 1) * samples.count / count)
      let slice = samples[start..<min(end, samples.count)].map(Double.init)
      return WaveformPoint(minimum: slice.min() ?? 0, maximum: slice.max() ?? 0)
    }
  }

  func downsample(points: [TimePoint], limit: Int) -> [TimePoint] {
    guard points.count > limit else { return points }
    return (0..<limit).map { points[$0 * (points.count - 1) / (limit - 1)] }
  }

}
