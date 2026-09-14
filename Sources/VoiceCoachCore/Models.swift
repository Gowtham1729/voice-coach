import Foundation

public struct TimePoint: Codable, Sendable, Equatable {
    public let time: Double
    public let value: Double

    public init(time: Double, value: Double) {
        self.time = time
        self.value = value
    }
}

public struct WaveformPoint: Codable, Sendable, Equatable {
    public let minimum: Double
    public let maximum: Double

    public init(minimum: Double, maximum: Double) {
        self.minimum = minimum
        self.maximum = maximum
    }
}

public struct SpectrogramData: Codable, Sendable, Equatable {
    public let columns: Int
    public let rows: Int
    public let decibels: [Double]

    public init(columns: Int, rows: Int, decibels: [Double]) {
        self.columns = columns
        self.rows = rows
        self.decibels = decibels
    }
}

public struct VoiceMetrics: Codable, Sendable, Equatable {
    public let duration: Double
    public let activeSpeechDuration: Double
    public let sampleRateHz: Double
    public let noiseFloorDBFS: Double
    public let snrDB: Double
    public let clippingPercent: Double
    public let pauseCount: Int
    public let meanPauseMs: Double
    public let medianPauseMs: Double
    public let longestPauseMs: Double
    public let pauseRatio: Double
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
        pauseCount: Int,
        meanPauseMs: Double,
        medianPauseMs: Double,
        longestPauseMs: Double,
        pauseRatio: Double,
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
        self.pauseCount = pauseCount
        self.meanPauseMs = meanPauseMs
        self.medianPauseMs = medianPauseMs
        self.longestPauseMs = longestPauseMs
        self.pauseRatio = pauseRatio
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

public struct AnalysisResult: Codable, Sendable, Equatable {
    public let createdAt: Date
    public let metrics: VoiceMetrics
    public let loudnessContour: [TimePoint]
    public let pitchContour: [TimePoint]
    public let waveform: [WaveformPoint]
    public let spectrogram: SpectrogramData

    public init(
        createdAt: Date = Date(),
        metrics: VoiceMetrics,
        loudnessContour: [TimePoint],
        pitchContour: [TimePoint],
        waveform: [WaveformPoint],
        spectrogram: SpectrogramData
    ) {
        self.createdAt = createdAt
        self.metrics = metrics
        self.loudnessContour = loudnessContour
        self.pitchContour = pitchContour
        self.waveform = waveform
        self.spectrogram = spectrogram
    }
}

public struct PracticeSession: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let audioURL: URL
    public let result: AnalysisResult

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        audioURL: URL,
        result: AnalysisResult
    ) {
        self.id = id
        self.createdAt = createdAt
        self.audioURL = audioURL
        self.result = result
    }
}
