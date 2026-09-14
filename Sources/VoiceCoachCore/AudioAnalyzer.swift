import AVFoundation
import Foundation

public enum AnalysisError: LocalizedError {
    case emptyRecording
    case unreadableAudio

    public var errorDescription: String? {
        switch self {
        case .emptyRecording: "The recording is empty."
        case .unreadableAudio: "The audio file could not be decoded."
        }
    }
}

public struct AudioAnalyzer: Sendable {
    public init() {}

    public func analyze(url: URL) throws -> AnalysisResult {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { throw AnalysisError.emptyRecording }

        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { throw AnalysisError.unreadableAudio }

        let channelCount = Int(format.channelCount)
        let count = Int(buffer.frameLength)
        var samples = [Float](repeating: 0, count: count)
        for channel in 0..<channelCount {
            for index in 0..<count {
                samples[index] += channels[channel][index] / Float(channelCount)
            }
        }
        return analyze(samples: samples, sampleRate: format.sampleRate)
    }

    public func analyze(samples: [Float], sampleRate: Double) -> AnalysisResult {
        guard !samples.isEmpty, sampleRate > 0 else {
            return emptyResult
        }

        let duration = Double(samples.count) / sampleRate
        let frameSize = min(2048, max(256, nextPowerOfTwo(Int(sampleRate * 0.04))))
        let hopSize = max(frameSize / 2, 1)

        var loudness: [TimePoint] = []
        var pitch: [TimePoint] = []
        var hnrValues: [Double] = []
        var allFrameDB: [Double] = []

        var offset = 0
        while offset + frameSize <= samples.count {
            let frame = Array(samples[offset..<(offset + frameSize)])
            let rms = rootMeanSquare(frame)
            let db = amplitudeToDB(rms)
            let time = (Double(offset) + Double(frameSize) / 2) / sampleRate
            allFrameDB.append(db)
            loudness.append(TimePoint(time: time, value: db))

            if db > -50, let estimate = estimatePitch(frame: frame, sampleRate: sampleRate) {
                pitch.append(TimePoint(time: time, value: estimate.frequency))
                hnrValues.append(estimate.hnr)
            }
            offset += hopSize
        }

        if loudness.isEmpty {
            let db = amplitudeToDB(rootMeanSquare(samples))
            loudness = [TimePoint(time: duration / 2, value: db)]
            allFrameDB = [db]
        }

        let noiseFloor = percentile(allFrameDB, 0.15)
        let activeThreshold = min(-32, max(-50, noiseFloor + 8))
        let activeFrames = loudness.filter { $0.value >= activeThreshold }
        let activeDB = activeFrames.map(\.value)
        let activeSpeechDuration = min(duration, Double(activeFrames.count * hopSize) / sampleRate)
        let pauseRatio = duration > 0 ? max(0, 1 - activeSpeechDuration / duration) : 0
        let meanDB = activeDB.isEmpty ? mean(allFrameDB) : mean(activeDB)
        let analysisDB = activeDB.isEmpty ? allFrameDB : activeDB
        let dynamicRange = max(0, percentile(analysisDB, 0.90) - percentile(analysisDB, 0.10))
        let loudnessDeviation = standardDeviation(analysisDB)
        let snr = max(0, meanDB - noiseFloor)
        let clippingPercent = Double(samples.lazy.filter { abs($0) >= 0.999 }.count) / Double(samples.count) * 100
        let pauses = pauseDurations(
            loudness: loudness,
            activeThreshold: activeThreshold,
            hopSize: hopSize,
            sampleRate: sampleRate
        )
        let pauseMilliseconds = pauses.map { $0 * 1_000 }

        let phraseValues = activeDB.isEmpty ? allFrameDB : activeDB
        let segmentCount = max(1, Int(Double(phraseValues.count) * 0.20))
        let startDB = median(Array(phraseValues.prefix(segmentCount)))
        let endDB = median(Array(phraseValues.suffix(segmentCount)))
        let phraseDecay = endDB - startDB

        let pitchValues = pitch.map(\.value)
        let medianPitch = optionalStatistic(pitchValues, median)
        let pitchLow = optionalStatistic(pitchValues) { percentile($0, 0.05) }
        let pitchHigh = optionalStatistic(pitchValues) { percentile($0, 0.95) }
        let pitchVariation = pitchValues.count > 1 ? standardDeviation(pitchValues) : nil
        let pitchRangeSemitones = semitoneDistance(low: pitchLow, high: pitchHigh)
        let pitchSemitones = pitchValues.compactMap { frequency -> Double? in
            guard let medianPitch, medianPitch > 0, frequency > 0 else { return nil }
            return 12 * log2(frequency / medianPitch)
        }
        let pitchDeviationSemitones = pitchSemitones.count > 1 ? standardDeviation(pitchSemitones) : nil
        let pitchInstability = relativeSuccessiveDifference(pitchValues)
        let cpp = cppSummary(samples: samples, sampleRate: sampleRate)
        let metrics = VoiceMetrics(
            duration: duration,
            activeSpeechDuration: activeSpeechDuration,
            sampleRateHz: sampleRate,
            noiseFloorDBFS: noiseFloor,
            snrDB: snr,
            clippingPercent: clippingPercent,
            pauseCount: pauseMilliseconds.count,
            meanPauseMs: mean(pauseMilliseconds),
            medianPauseMs: median(pauseMilliseconds),
            longestPauseMs: pauseMilliseconds.max() ?? 0,
            pauseRatio: pauseRatio,
            meanLoudnessDBFS: meanDB,
            loudnessDynamicRangeDB: dynamicRange,
            loudnessStandardDeviationDB: loudnessDeviation,
            phraseStartDBFS: startDB,
            phraseEndDBFS: endDB,
            phraseDecayDB: phraseDecay,
            medianPitchHz: medianPitch,
            pitchLowHz: pitchLow,
            pitchHighHz: pitchHigh,
            pitchVariationHz: pitchVariation,
            pitchRangeSemitones: pitchRangeSemitones,
            pitchStandardDeviationSemitones: pitchDeviationSemitones,
            pitchInstabilityPercent: pitchInstability,
            hnrDB: hnrValues.isEmpty ? nil : median(hnrValues),
            cppDB: cpp
        )

        return AnalysisResult(
            metrics: metrics,
            loudnessContour: downsample(points: loudness, limit: 300),
            pitchContour: downsample(points: pitch, limit: 300),
            waveform: waveform(samples: samples, bins: 420),
            spectrogram: makeSpectrogram(samples: samples, sampleRate: sampleRate),
            acousticFrames: AcousticFrameData(loudness: loudness, pitch: pitch)
        )
    }

    private var emptyResult: AnalysisResult {
        AnalysisResult(
            metrics: VoiceMetrics(
                duration: 0, activeSpeechDuration: 0, sampleRateHz: 0,
                noiseFloorDBFS: -80, snrDB: 0, clippingPercent: 0,
                pauseCount: 0, meanPauseMs: 0, medianPauseMs: 0, longestPauseMs: 0,
                pauseRatio: 0, meanLoudnessDBFS: -80,
                loudnessDynamicRangeDB: 0, loudnessStandardDeviationDB: 0, phraseStartDBFS: -80,
                phraseEndDBFS: -80, phraseDecayDB: 0,
                medianPitchHz: nil, pitchLowHz: nil, pitchHighHz: nil,
                pitchVariationHz: nil, pitchRangeSemitones: nil,
                pitchStandardDeviationSemitones: nil, pitchInstabilityPercent: nil,
                hnrDB: nil, cppDB: nil
            ),
            loudnessContour: [], pitchContour: [], waveform: [],
            spectrogram: SpectrogramData(columns: 0, rows: 0, decibels: [])
        )
    }
}

private extension AudioAnalyzer {
    struct PitchEstimate {
        let frequency: Double
        let hnr: Double
    }

    func estimatePitch(frame: [Float], sampleRate: Double) -> PitchEstimate? {
        let decimation = sampleRate > 32_000 ? 2 : 1
        let signal = stride(from: 0, to: frame.count, by: decimation).map { Double(frame[$0]) }
        let rate = sampleRate / Double(decimation)
        let minimumLag = max(2, Int(rate / 500))
        let maximumLag = min(signal.count / 2, Int(rate / 70))
        guard maximumLag > minimumLag else { return nil }

        let average = mean(signal)
        var centered = signal.map { $0 - average }
        for index in centered.indices {
            let window = 0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(max(centered.count - 1, 1)))
            centered[index] *= window
        }

        var difference = [Double](repeating: 0, count: maximumLag + 1)
        for lag in minimumLag...maximumLag {
            var sum = 0.0
            let limit = centered.count - lag
            for index in 0..<limit {
                let delta = centered[index] - centered[index + lag]
                sum += delta * delta
            }
            difference[lag] = sum
        }

        var cumulative = 0.0
        var normalized = [Double](repeating: 1, count: maximumLag + 1)
        for lag in 1...maximumLag {
            cumulative += difference[lag]
            normalized[lag] = cumulative > 0 ? difference[lag] * Double(lag) / cumulative : 1
        }

        var selectedLag: Int?
        var lag = minimumLag
        while lag < maximumLag {
            if normalized[lag] < 0.18 {
                while lag + 1 <= maximumLag, normalized[lag + 1] < normalized[lag] { lag += 1 }
                selectedLag = lag
                break
            }
            lag += 1
        }
        if selectedLag == nil,
           let fallback = (minimumLag...maximumLag).min(by: { normalized[$0] < normalized[$1] }),
           normalized[fallback] < 0.32 {
            selectedLag = fallback
        }
        guard let chosen = selectedLag else { return nil }

        var refined = Double(chosen)
        if chosen > minimumLag, chosen < maximumLag {
            let left = normalized[chosen - 1]
            let center = normalized[chosen]
            let right = normalized[chosen + 1]
            let denominator = left - 2 * center + right
            if abs(denominator) > 1e-12 {
                refined += 0.5 * (left - right) / denominator
            }
        }

        let frequency = rate / refined
        guard frequency >= 70, frequency <= 500 else { return nil }

        var numerator = 0.0
        var energyA = 0.0
        var energyB = 0.0
        let correlationLimit = centered.count - chosen
        for index in 0..<correlationLimit {
            numerator += centered[index] * centered[index + chosen]
            energyA += centered[index] * centered[index]
            energyB += centered[index + chosen] * centered[index + chosen]
        }
        let correlation = max(0.001, min(0.999, numerator / sqrt(max(energyA * energyB, 1e-12))))
        guard correlation >= 0.45 else { return nil }
        let hnr = 10 * log10(correlation / (1 - correlation))
        return PitchEstimate(frequency: frequency, hnr: hnr)
    }

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
        let slope = denominator > 0
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

private func rootMeanSquare(_ samples: [Float]) -> Double {
    guard !samples.isEmpty else { return 0 }
    return sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count))
}

private func amplitudeToDB(_ amplitude: Double) -> Double {
    max(-80, 20 * log10(max(amplitude, 0.0001)))
}

private func mean(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
}

private func median(_ values: [Double]) -> Double {
    percentile(values, 0.5)
}

private func percentile(_ values: [Double], _ percentile: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let position = max(0, min(1, percentile)) * Double(sorted.count - 1)
    let lower = Int(floor(position))
    let upper = Int(ceil(position))
    guard lower != upper else { return sorted[lower] }
    let fraction = position - Double(lower)
    return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
}

private func standardDeviation(_ values: [Double]) -> Double {
    let average = mean(values)
    return sqrt(mean(values.map { pow($0 - average, 2) }))
}

private func relativeSuccessiveDifference(_ values: [Double]) -> Double? {
    guard values.count > 1 else { return nil }
    let differences = zip(values, values.dropFirst()).map { abs($1 - $0) }
    let average = mean(values)
    return average > 0 ? mean(differences) / average * 100 : nil
}

private func semitoneDistance(low: Double?, high: Double?) -> Double? {
    guard let low, let high, low > 0, high > 0 else { return nil }
    return 12 * log2(high / low)
}

private func optionalStatistic(_ values: [Double], _ operation: ([Double]) -> Double) -> Double? {
    values.isEmpty ? nil : operation(values)
}

private func nextPowerOfTwo(_ value: Int) -> Int {
    guard value > 1 else { return 1 }
    var result = 1
    while result < value { result *= 2 }
    return result
}
