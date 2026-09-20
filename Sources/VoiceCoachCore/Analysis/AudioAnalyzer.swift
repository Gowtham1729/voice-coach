import Foundation

#if canImport(AVFoundation)
  import AVFoundation
#endif

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

  #if canImport(AVFoundation)
    public func analyze(url: URL) throws -> AnalysisResult {
      let file = try AVAudioFile(forReading: url)
      let format = file.processingFormat
      guard file.length > 0,
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_192)
      else { throw AnalysisError.emptyRecording }

      let channelCount = Int(format.channelCount)
      var samples: [Float] = []
      samples.reserveCapacity(Int(file.length))
      while file.framePosition < file.length {
        try file.read(into: buffer, frameCount: buffer.frameCapacity)
        guard buffer.frameLength > 0,
          let channels = buffer.floatChannelData
        else { break }
        for index in 0..<Int(buffer.frameLength) {
          var value: Float = 0
          for channel in 0..<channelCount {
            value += channels[channel][index] / Float(channelCount)
          }
          samples.append(value)
        }
      }
      guard !samples.isEmpty else { throw AnalysisError.unreadableAudio }
      return analyze(samples: samples, sampleRate: format.sampleRate)
    }
  #endif

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
    let clippingPercent =
      Double(samples.lazy.filter { abs($0) >= 0.999 }.count) / Double(samples.count) * 100

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
