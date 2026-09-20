import Foundation

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
        if let sub = estimate.candidates.first(where: {
          abs($0.lag - halfLag) < 4.0 && $0.depth < 0.35
        }) {
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
          if let fund = estimate.candidates.first(where: {
            abs($0.lag - targetLag) < 4.0 * mult && $0.depth < 0.35
          }) {
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
      let hasPrev =
        isPitchContinuous(pt, i > 0 ? correctedTrack[i - 1] : nil)
        || isPitchContinuous(pt, i > 1 ? correctedTrack[i - 2] : nil)
      let hasNext =
        isPitchContinuous(pt, i + 1 < correctedTrack.count ? correctedTrack[i + 1] : nil)
        || isPitchContinuous(pt, i + 2 < correctedTrack.count ? correctedTrack[i + 2] : nil)
      if hasPrev || hasNext || correctedTrack.count == 1 {
        pitchPoints.append(TimePoint(time: pt.time, value: pt.frequency))
        hnrValues.append(pt.hnr)
      }
    }

    return (pitchPoints, hnrValues)
  }

  private func isPitchContinuous(
    _ a: PitchPoint?, _ b: PitchPoint?, thresholdSemitones: Double = 8.0
  ) -> Bool {
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
        let lastPt = current[lastIdx]
      else { continue }

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

            if let newFreq = harmonicCorrection(frequency: pt.frequency, contextFrequency: ctxFreq)
            {
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
        let lastPt = current[lastIdx]
      else { continue }

      // Onset check
      if hasPrecedingGap(at: m, clusters: clusters, track: current) && m + 1 < clusters.count {
        let nextCluster = clusters[m + 1]
        if let nextFirstIdx = nextCluster.first,
          let nextFirstPt = current[nextFirstIdx],
          (nextFirstPt.time - lastPt.time) <= 0.045,
          nextCluster.count >= max(5, cluster.count + 2),
          let factor = edgeCorrectionFactor(
            clusterFrequency: lastPt.frequency, anchorFrequency: nextFirstPt.frequency)
        {
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
          let factor = edgeCorrectionFactor(
            clusterFrequency: firstPt.frequency, anchorFrequency: prevLastPt.frequency)
        {
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

  private func hasPrecedingGap(
    at clusterIndex: Int, clusters: [[Int]], track: [PitchPoint?], threshold: Double = 0.050
  ) -> Bool {
    guard clusterIndex > 0,
      let prevLastIdx = clusters[clusterIndex - 1].last,
      let prevLastPt = track[prevLastIdx],
      let currFirstIdx = clusters[clusterIndex].first,
      let currFirstPt = track[currFirstIdx]
    else {
      return true
    }
    return (currFirstPt.time - prevLastPt.time) > threshold
  }

  private func hasFollowingGap(
    at clusterIndex: Int, clusters: [[Int]], track: [PitchPoint?], threshold: Double = 0.050
  ) -> Bool {
    guard clusterIndex + 1 < clusters.count,
      let currLastIdx = clusters[clusterIndex].last,
      let currLastPt = track[currLastIdx],
      let nextFirstIdx = clusters[clusterIndex + 1].first,
      let nextFirstPt = track[nextFirstIdx]
    else {
      return true
    }
    return (nextFirstPt.time - currLastPt.time) > threshold
  }
}
