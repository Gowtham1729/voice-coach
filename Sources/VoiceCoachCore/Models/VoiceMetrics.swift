import Foundation

public struct VoiceMetrics: Codable, Sendable, Equatable {
  public let duration: Double
  public let activeSpeechDuration: Double
  public let sampleRateHz: Double
  public let noiseFloorDBFS: Double
  public let snrDB: Double
  public let clippingPercent: Double
  public let nonSpeechRatio: Double
  public let internalPauseCount: Int
  public let internalPauseTotalMs: Double
  public let meanInternalPauseMs: Double
  public let medianInternalPauseMs: Double
  public let longestInternalPauseMs: Double
  public let leadingSilenceMs: Double
  public let trailingSilenceMs: Double
  public let meanLoudnessDBFS: Double
  public let loudnessDynamicRangeDB: Double
  public let loudnessStandardDeviationDB: Double
  public let phraseStartDBFS: Double
  public let phraseEndDBFS: Double
  public let phraseDecayDB: Double
  public let medianPitchHz: Double?
  public let pitchLowHz: Double?
  public let pitchHighHz: Double?
  public let pitchVariationHz: Double?
  public let pitchRangeSemitones: Double?
  public let pitchStandardDeviationSemitones: Double?
  public let pitchInstabilityPercent: Double?
  public let hnrDB: Double?
  public let cppDB: Double?

  public init(
    duration: Double,
    activeSpeechDuration: Double,
    sampleRateHz: Double,
    noiseFloorDBFS: Double,
    snrDB: Double,
    clippingPercent: Double,
    nonSpeechRatio: Double,
    internalPauseCount: Int,
    internalPauseTotalMs: Double,
    meanInternalPauseMs: Double,
    medianInternalPauseMs: Double,
    longestInternalPauseMs: Double,
    leadingSilenceMs: Double,
    trailingSilenceMs: Double,
    meanLoudnessDBFS: Double,
    loudnessDynamicRangeDB: Double,
    loudnessStandardDeviationDB: Double,
    phraseStartDBFS: Double,
    phraseEndDBFS: Double,
    phraseDecayDB: Double,
    medianPitchHz: Double?,
    pitchLowHz: Double?,
    pitchHighHz: Double?,
    pitchVariationHz: Double?,
    pitchRangeSemitones: Double?,
    pitchStandardDeviationSemitones: Double?,
    pitchInstabilityPercent: Double?,
    hnrDB: Double?,
    cppDB: Double?
  ) {
    self.duration = duration
    self.activeSpeechDuration = activeSpeechDuration
    self.sampleRateHz = sampleRateHz
    self.noiseFloorDBFS = noiseFloorDBFS
    self.snrDB = snrDB
    self.clippingPercent = clippingPercent
    self.nonSpeechRatio = nonSpeechRatio
    self.internalPauseCount = internalPauseCount
    self.internalPauseTotalMs = internalPauseTotalMs
    self.meanInternalPauseMs = meanInternalPauseMs
    self.medianInternalPauseMs = medianInternalPauseMs
    self.longestInternalPauseMs = longestInternalPauseMs
    self.leadingSilenceMs = leadingSilenceMs
    self.trailingSilenceMs = trailingSilenceMs
    self.meanLoudnessDBFS = meanLoudnessDBFS
    self.loudnessDynamicRangeDB = loudnessDynamicRangeDB
    self.loudnessStandardDeviationDB = loudnessStandardDeviationDB
    self.phraseStartDBFS = phraseStartDBFS
    self.phraseEndDBFS = phraseEndDBFS
    self.phraseDecayDB = phraseDecayDB
    self.medianPitchHz = medianPitchHz
    self.pitchLowHz = pitchLowHz
    self.pitchHighHz = pitchHighHz
    self.pitchVariationHz = pitchVariationHz
    self.pitchRangeSemitones = pitchRangeSemitones
    self.pitchStandardDeviationSemitones = pitchStandardDeviationSemitones
    self.pitchInstabilityPercent = pitchInstabilityPercent
    self.hnrDB = hnrDB
    self.cppDB = cppDB
  }
}
