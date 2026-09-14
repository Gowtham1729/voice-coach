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
        // 10 ms hop size (100 fps) for dense, reliable acoustic and pitch resolution
        let hopSize = max(1, Int(sampleRate * 0.010))
        // 40 ms analysis frame window
        let frameSize = min(samples.count, max(hopSize * 2, Int(sampleRate * 0.040)))

        let decimation = sampleRate > 32_000 ? 2 : 1
        let rate = sampleRate / Double(decimation)
        let minimumLag = max(2, Int(rate / 500))
        let maximumLag = min(Int(Double(frameSize / decimation) / 2), Int(rate / 70))

        var loudness: [TimePoint] = []
        var allFrameDB: [Double] = []
        var rawFrames: [(time: Double, db: Double, frame: [Float])] = []

        var offset = 0
        while offset + frameSize <= samples.count {
            let frame = Array(samples[offset..<(offset + frameSize)])
            let rms = rootMeanSquare(frame)
            let db = amplitudeToDB(rms)
            let time = (Double(offset) + Double(frameSize) / 2) / sampleRate
            allFrameDB.append(db)
            loudness.append(TimePoint(time: time, value: db))
            rawFrames.append((time: time, db: db, frame: frame))
            offset += hopSize
        }

        if loudness.isEmpty {
            let db = amplitudeToDB(rootMeanSquare(samples))
            loudness = [TimePoint(time: duration / 2, value: db)]
            allFrameDB = [db]
        }

        let noiseFloor = percentile(allFrameDB, 0.15)
        let activeThreshold = min(-32, max(-50, noiseFloor + 8))
        let pitchThreshold = min(-32, max(-48, activeThreshold - 3))

        var frameEstimates: [PitchFrameEstimate] = []
        for f in rawFrames {
            var candidates: [PitchCandidate] = []
            if f.db >= pitchThreshold, maximumLag > minimumLag {
                candidates = extractCandidates(
                    frame: f.frame,
                    rate: rate,
                    decimation: decimation,
                    minimumLag: minimumLag,
                    maximumLag: maximumLag
                )
            }
            frameEstimates.append(PitchFrameEstimate(time: f.time, db: f.db, candidates: candidates))
        }

        let tracking = trackPitch(frameEstimates: frameEstimates)
        let pitch = tracking.pitchPoints
        let hnrValues = tracking.hnrValues
        let activeFrames = loudness.filter { $0.value >= activeThreshold }
        let activeDB = activeFrames.map(\.value)
        let activeSpeechDuration = min(duration, Double(activeFrames.count * hopSize) / sampleRate)
        let nonSpeechRatio = duration > 0 ? max(0, 1 - activeSpeechDuration / duration) : 0
        let meanDB = activeDB.isEmpty ? mean(allFrameDB) : mean(activeDB)
        let analysisDB = activeDB.isEmpty ? allFrameDB : activeDB
        let dynamicRange = max(0, percentile(analysisDB, 0.90) - percentile(analysisDB, 0.10))
        let loudnessDeviation = standardDeviation(analysisDB)
        let snr = max(0, meanDB - noiseFloor)
        let clippingPercent = Double(samples.lazy.filter { abs($0) >= 0.999 }.count) / Double(samples.count) * 100

        let activeMask = loudness.map { $0.value >= activeThreshold }
        let firstActiveIndex = activeMask.firstIndex(of: true)
        let lastActiveIndex = activeMask.lastIndex(of: true)

        let leadingSilenceMs: Double
        let trailingSilenceMs: Double
        if let firstActiveIndex, let lastActiveIndex {
            leadingSilenceMs = max(0, Double(firstActiveIndex * hopSize) / sampleRate * 1_000)
            let lastActiveEndTime = min(duration, Double((lastActiveIndex + 1) * hopSize) / sampleRate)
            trailingSilenceMs = max(0, (duration - lastActiveEndTime) * 1_000)
        } else {
            leadingSilenceMs = duration * 1_000
            trailingSilenceMs = 0
        }

        let pauses = pauseDurations(
            loudness: loudness,
            activeThreshold: activeThreshold,
            hopSize: hopSize,
            sampleRate: sampleRate
        )
        let pauseMilliseconds = pauses.map { $0 * 1_000 }
        let internalPauseCount = pauseMilliseconds.count
        let internalPauseTotalMs = pauseMilliseconds.reduce(0, +)
        let meanInternalPauseMs = mean(pauseMilliseconds)
        let medianInternalPauseMs = median(pauseMilliseconds)
        let longestInternalPauseMs = pauseMilliseconds.max() ?? 0

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
            nonSpeechRatio: nonSpeechRatio,
            internalPauseCount: internalPauseCount,
            internalPauseTotalMs: internalPauseTotalMs,
            meanInternalPauseMs: meanInternalPauseMs,
            medianInternalPauseMs: medianInternalPauseMs,
            longestInternalPauseMs: longestInternalPauseMs,
            leadingSilenceMs: leadingSilenceMs,
            trailingSilenceMs: trailingSilenceMs,
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
                nonSpeechRatio: 0, internalPauseCount: 0, internalPauseTotalMs: 0,
                meanInternalPauseMs: 0, medianInternalPauseMs: 0, longestInternalPauseMs: 0,
                leadingSilenceMs: 0, trailingSilenceMs: 0,
                meanLoudnessDBFS: -80,
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

extension AudioAnalyzer {
    struct PitchCandidate {
        let lag: Double
        let frequency: Double
        let depth: Double
    }

    struct PitchFrameEstimate {
        let time: Double
        let db: Double
        let candidates: [PitchCandidate]
    }

    public struct PitchPoint: Sendable {
        public let time: Double
        public let frequency: Double
        public let hnr: Double

        public init(time: Double, frequency: Double, hnr: Double) {
            self.time = time
            self.frequency = frequency
            self.hnr = hnr
        }
    }

    func extractCandidates(
        frame: [Float],
        rate: Double,
        decimation: Int,
        minimumLag: Int,
        maximumLag: Int
    ) -> [PitchCandidate] {
        guard frame.count > maximumLag else { return [] }
        let signal = stride(from: 0, to: frame.count, by: decimation).map { Double(frame[$0]) }
        guard signal.count > maximumLag else { return [] }
        let avg = signal.reduce(0.0, +) / Double(signal.count)
        let centered = signal.map { $0 - avg }

        let integrationWindow = signal.count - maximumLag
        guard integrationWindow > 0 else { return [] }

        var difference = [Double](repeating: 0, count: maximumLag + 1)
        for lag in 1...maximumLag {
            var sum = 0.0
            for j in 0..<integrationWindow {
                let delta = centered[j] - centered[j + lag]
                sum += delta * delta
            }
            difference[lag] = sum
        }

        var cmndf = [Double](repeating: 1, count: maximumLag + 1)
        var cumulative = 0.0
        for lag in 1...maximumLag {
            cumulative += difference[lag]
            cmndf[lag] = cumulative > 0 ? difference[lag] * Double(lag) / cumulative : 1.0
        }

        var candidates: [PitchCandidate] = []
        for lag in (minimumLag + 1)..<maximumLag {
            if cmndf[lag] < cmndf[lag - 1] && cmndf[lag] < cmndf[lag + 1] {
                let left = cmndf[lag - 1]
                let center = cmndf[lag]
                let right = cmndf[lag + 1]
                let denom = left - 2 * center + right
                var refinedLag = Double(lag)
                var refinedDepth = center
                if abs(denom) > 1e-12 {
                    let delta = 0.5 * (left - right) / denom
                    refinedLag += delta
                    refinedDepth = center - 0.25 * (left - right) * delta
                }
                let freq = rate / refinedLag
                if freq >= 70 && freq <= 500 && refinedDepth < 0.50 {
                    // Suppress low-frequency room rumble (sub-85 Hz) unless deeply periodic
                    if freq < 85 && refinedDepth > 0.18 { continue }
                    candidates.append(PitchCandidate(lag: refinedLag, frequency: freq, depth: refinedDepth))
                }
            }
        }
        return candidates
    }

    func trackPitch(
        frameEstimates: [PitchFrameEstimate]
    ) -> (pitchPoints: [TimePoint], hnrValues: [Double]) {
        var rawTrack = [PitchPoint?](repeating: nil, count: frameEstimates.count)
        var prevFreq: Double? = nil

        for i in 0..<frameEstimates.count {
            let estimate = frameEstimates[i]
            if estimate.candidates.isEmpty {
                prevFreq = nil
                continue
            }

            // Subharmonic Octave Check:
            // If candidate is near 2 * another candidate with good depth, prefer the fundamental (smaller lag)
            var refined = estimate.candidates
            for candidate in estimate.candidates {
                let halfLag = candidate.lag / 2.0
                if let sub = estimate.candidates.first(where: { abs($0.lag - halfLag) < 4.0 && $0.depth < 0.35 }) {
                    if let idx = refined.firstIndex(where: { $0.lag == candidate.lag }) {
                        refined[idx] = sub
                    }
                }
            }

            // Harmonic Formant Check:
            // If candidate is high frequency (> 380 Hz), check if integer multiple 2x or 3x lag exists with depth < 0.35
            for candidate in refined where candidate.frequency > 380 {
                for mult in [2.0, 3.0] {
                    let targetLag = candidate.lag * mult
                    if let fund = estimate.candidates.first(where: { abs($0.lag - targetLag) < 4.0 * mult && $0.depth < 0.35 }) {
                        if let idx = refined.firstIndex(where: { $0.lag == candidate.lag }) {
                            refined[idx] = fund
                        }
                    }
                }
            }

            let sortedByLag = refined.sorted { $0.lag < $1.lag }
            let primary = sortedByLag.first { $0.depth < 0.20 }

            let best: PitchCandidate?
            if let prev = prevFreq {
                // Continuity check: prefer staying within 6 semitones of ongoing track
                let continuous = refined.filter {
                    abs(12 * log2($0.frequency / prev)) < 6.0 && $0.depth < 0.35
                }.min(by: { $0.depth < $1.depth })

                if let continuous {
                    best = continuous
                } else if let primary, abs(12 * log2(primary.frequency / prev)) < 10.0 {
                    best = primary
                } else {
                    // Large jump: only accept if very confident (depth < 0.15)
                    best = refined.filter { $0.depth < 0.15 }.min(by: { $0.depth < $1.depth })
                }
            } else {
                if let primary {
                    best = primary
                } else {
                    best = refined.min(by: { $0.depth < $1.depth }).flatMap { $0.depth < 0.28 ? $0 : nil }
                }
            }

            if let chosen = best {
                let hnr = 10 * log10(max(0.01, 1 - chosen.depth) / max(0.001, chosen.depth))
                rawTrack[i] = PitchPoint(time: estimate.time, frequency: chosen.frequency, hnr: hnr)
                prevFreq = chosen.frequency
            } else {
                prevFreq = nil
            }
        }

        // Apply continuity-aware octave-error correction and outlier rejection
        let correctedTrack = correctOctaveErrorsAndOutliers(track: rawTrack)

        // Remove isolated singletons (must have a pitch-continuous neighbor within 8 semitones)
        var pitchPoints: [TimePoint] = []
        var hnrValues: [Double] = []
        for i in 0..<correctedTrack.count {
            guard let pt = correctedTrack[i] else { continue }
            let hasPrev = isPitchContinuous(pt, i > 0 ? correctedTrack[i - 1] : nil)
                || isPitchContinuous(pt, i > 1 ? correctedTrack[i - 2] : nil)
            let hasNext = isPitchContinuous(pt, i + 1 < correctedTrack.count ? correctedTrack[i + 1] : nil)
                || isPitchContinuous(pt, i + 2 < correctedTrack.count ? correctedTrack[i + 2] : nil)
            if hasPrev || hasNext || correctedTrack.count == 1 {
                pitchPoints.append(TimePoint(time: pt.time, value: pt.frequency))
                hnrValues.append(pt.hnr)
            }
        }

        return (pitchPoints, hnrValues)
    }

    private func isPitchContinuous(_ a: PitchPoint?, _ b: PitchPoint?, thresholdSemitones: Double = 8.0) -> Bool {
        guard let a, let b else { return false }
        return abs(12 * log2(a.frequency / b.frequency)) < thresholdSemitones
    }

    /// Continuity-aware octave-error correction and outlier rejection.
    /// Detects temporary octave jumps (+-12 semitones or integer harmonics) relative to surrounding
    /// valid context and corrects them while strictly preserving genuine expressive pitch glides,
    /// and rejects isolated F0 outliers that strongly disagree with both neighboring frames.
    public func correctOctaveErrorsAndOutliers(
        track: [PitchPoint?]
    ) -> [PitchPoint?] {
        var current = track
        guard current.count >= 3 else { return current }

        // Group valid frames into contiguous smooth clusters
        let validIndices = current.indices.filter { current[$0] != nil }
        guard !validIndices.isEmpty else { return current }

        var clusters: [[Int]] = []
        var currentCluster: [Int] = []

        for idx in validIndices {
            if let lastIdx = currentCluster.last {
                let prevPt = current[lastIdx]!
                let currPt = current[idx]!
                let dt = currPt.time - prevPt.time
                let step = abs(12 * log2(currPt.frequency / prevPt.frequency))
                if dt <= 0.040 && step <= 3.5 {
                    currentCluster.append(idx)
                } else {
                    clusters.append(currentCluster)
                    currentCluster = [idx]
                }
            } else {
                currentCluster = [idx]
            }
        }
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        guard clusters.count >= 2 else { return current }

        // Pass 1: Bridged clusters (short runs of length 1 to 7 between two clusters)
        for m in 1..<(clusters.count - 1) {
            let cluster = clusters[m]
            guard cluster.count <= 7 else { continue }

            let prevCluster = clusters[m - 1]
            let nextCluster = clusters[m + 1]

            guard let prevIdx = prevCluster.last,
                  let nextIdx = nextCluster.first,
                  let firstIdx = cluster.first,
                  let lastIdx = cluster.last,
                  let beforePt = current[prevIdx],
                  let afterPt = current[nextIdx],
                  let firstPt = current[firstIdx],
                  let lastPt = current[lastIdx] else { continue }

            let dtBefore = firstPt.time - beforePt.time
            let dtAfter = afterPt.time - lastPt.time

            if dtBefore <= 0.050 && dtAfter <= 0.050 {
                let beforeFreq = beforePt.frequency
                let afterFreq = afterPt.frequency
                let bridgeDiff = abs(12 * log2(afterFreq / beforeFreq))

                if bridgeDiff <= 4.5 {
                    var allCorrected = true
                    var corrected: [(Int, Double)] = []

                    for k in cluster {
                        guard let pt = current[k] else { continue }
                        let totalDt = afterPt.time - beforePt.time
                        let alpha = totalDt > 0 ? (pt.time - beforePt.time) / totalDt : 0.5
                        let ctxFreq = beforeFreq * pow(afterFreq / beforeFreq, alpha)

                        if let newFreq = harmonicCorrection(frequency: pt.frequency, contextFrequency: ctxFreq) {
                            corrected.append((k, newFreq))
                        } else {
                            allCorrected = false
                            break
                        }
                    }

                    if allCorrected && !corrected.isEmpty {
                        for (k, f) in corrected {
                            if let orig = current[k] {
                                current[k] = PitchPoint(time: orig.time, frequency: f, hnr: orig.hnr)
                            }
                        }
                    } else if cluster.count == 1, let pt = current[cluster[0]] {
                        let totalDt = afterPt.time - beforePt.time
                        let alpha = totalDt > 0 ? (pt.time - beforePt.time) / totalDt : 0.5
                        let ctxFreq = beforeFreq * pow(afterFreq / beforeFreq, alpha)
                        let delta = abs(12 * log2(pt.frequency / ctxFreq))
                        if delta > 6.0 && bridgeDiff <= 3.5 {
                            current[cluster[0]] = nil
                        }
                    }
                }
            }
        }

        // Pass 2: Edge clusters (onset or offset)
        for m in 0..<clusters.count {
            let cluster = clusters[m]
            guard cluster.count <= 7,
                  let firstIdx = cluster.first,
                  let lastIdx = cluster.last,
                  let firstPt = current[firstIdx],
                  let lastPt = current[lastIdx] else { continue }

            // Onset check
            if hasPrecedingGap(at: m, clusters: clusters, track: current) && m + 1 < clusters.count {
                let nextCluster = clusters[m + 1]
                if let nextFirstIdx = nextCluster.first,
                   let nextFirstPt = current[nextFirstIdx],
                   (nextFirstPt.time - lastPt.time) <= 0.045,
                   nextCluster.count >= max(5, cluster.count + 2),
                   let factor = edgeCorrectionFactor(clusterFrequency: lastPt.frequency, anchorFrequency: nextFirstPt.frequency) {
                    scaleCluster(cluster, factor: factor, in: &current)
                }
            }

            // Offset check
            if hasFollowingGap(at: m, clusters: clusters, track: current) && m > 0 {
                let prevCluster = clusters[m - 1]
                if let prevLastIdx = prevCluster.last,
                   let prevLastPt = current[prevLastIdx],
                   (firstPt.time - prevLastPt.time) <= 0.045,
                   prevCluster.count >= max(5, cluster.count + 2),
                   let factor = edgeCorrectionFactor(clusterFrequency: firstPt.frequency, anchorFrequency: prevLastPt.frequency) {
                    scaleCluster(cluster, factor: factor, in: &current)
                }
            }
        }

        return current
    }

    private func harmonicCorrection(frequency: Double, contextFrequency: Double) -> Double? {
        let delta = 12 * log2(frequency / contextFrequency)
        if delta >= 10.5 && delta <= 13.5 {
            return frequency / 2.0
        } else if delta >= -13.5 && delta <= -10.5 {
            return frequency * 2.0
        } else if delta >= 17.5 && delta <= 20.5 {
            return frequency / 3.0
        } else if delta >= -20.5 && delta <= -17.5 {
            return frequency * 3.0
        }
        return nil
    }

    private func edgeCorrectionFactor(clusterFrequency: Double, anchorFrequency: Double) -> Double? {
        let jump = 12 * log2(clusterFrequency / anchorFrequency)
        if jump >= 10.5 && jump <= 13.5 {
            return 0.5
        } else if jump >= -13.5 && jump <= -10.5 {
            return 2.0
        }
        return nil
    }

    private func scaleCluster(_ indices: [Int], factor: Double, in track: inout [PitchPoint?]) {
        for k in indices {
            if let orig = track[k] {
                track[k] = PitchPoint(time: orig.time, frequency: orig.frequency * factor, hnr: orig.hnr)
            }
        }
    }

    private func hasPrecedingGap(at clusterIndex: Int, clusters: [[Int]], track: [PitchPoint?], threshold: Double = 0.050) -> Bool {
        guard clusterIndex > 0,
              let prevLastIdx = clusters[clusterIndex - 1].last,
              let prevLastPt = track[prevLastIdx],
              let currFirstIdx = clusters[clusterIndex].first,
              let currFirstPt = track[currFirstIdx] else {
            return true
        }
        return (currFirstPt.time - prevLastPt.time) > threshold
    }

    private func hasFollowingGap(at clusterIndex: Int, clusters: [[Int]], track: [PitchPoint?], threshold: Double = 0.050) -> Bool {
        guard clusterIndex + 1 < clusters.count,
              let currLastIdx = clusters[clusterIndex].last,
              let currLastPt = track[currLastIdx],
              let nextFirstIdx = clusters[clusterIndex + 1].first,
              let nextFirstPt = track[nextFirstIdx] else {
            return true
        }
        return (nextFirstPt.time - currLastPt.time) > threshold
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
