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

/// Full-resolution analysis frames used for timestamp-aligned calculations.
/// These stay out of the compact report and are separate from the downsampled UI contours.
public struct AcousticFrameData: Codable, Sendable, Equatable {
    public let loudness: [TimePoint]
    public let pitch: [TimePoint]

    public init(loudness: [TimePoint], pitch: [TimePoint]) {
        self.loudness = loudness
        self.pitch = pitch
    }
}

public struct TranscriptWord: Codable, Sendable, Equatable {
    public let word: String
    public let start: Double
    public let end: Double
    public let confidence: Double?

    public init(word: String, start: Double, end: Double, confidence: Double? = nil) {
        self.word = word
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

public struct TranscriptionResult: Codable, Sendable, Equatable {
    public let text: String
    public let words: [TranscriptWord]

    public init(text: String, words: [TranscriptWord]) {
        self.text = text
        self.words = words
    }
}

public struct WordPitchMetrics: Codable, Sendable, Equatable {
    public let medianHz: Double?
    public let relativeMedianSemitones: Double?
    public let rangeSemitones: Double?
    public let startToEndSemitones: Double?
    public let validPitchFrames: Int
    public let pitchCoverage: Double

    public init(
        medianHz: Double?,
        relativeMedianSemitones: Double?,
        rangeSemitones: Double?,
        startToEndSemitones: Double?,
        validPitchFrames: Int = 0,
        pitchCoverage: Double = 0.0
    ) {
        self.medianHz = medianHz
        self.relativeMedianSemitones = relativeMedianSemitones
        self.rangeSemitones = rangeSemitones
        self.startToEndSemitones = startToEndSemitones
        self.validPitchFrames = validPitchFrames
        self.pitchCoverage = pitchCoverage
    }
}

public struct WordLoudnessMetrics: Codable, Sendable, Equatable {
    public let relativeMeanDB: Double?
    public let startToEndDB: Double?
    public let activeFrameCoverage: Double

    public init(
        relativeMeanDB: Double?,
        startToEndDB: Double?,
        activeFrameCoverage: Double = 0.0
    ) {
        self.relativeMeanDB = relativeMeanDB
        self.startToEndDB = startToEndDB
        self.activeFrameCoverage = activeFrameCoverage
    }
}

public struct WordAnalysis: Codable, Sendable, Equatable {
    public let word: String
    public let start: Double
    public let end: Double
    public let pitch: WordPitchMetrics
    public let loudness: WordLoudnessMetrics

    public init(
        word: String,
        start: Double,
        end: Double,
        pitch: WordPitchMetrics,
        loudness: WordLoudnessMetrics
    ) {
        self.word = word
        self.start = start
        self.end = end
        self.pitch = pitch
        self.loudness = loudness
    }
}

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

    public var pauseCount: Int { internalPauseCount }
    public var pauseRatio: Double { nonSpeechRatio }
    public var meanPauseMs: Double { meanInternalPauseMs }
    public var medianPauseMs: Double { medianInternalPauseMs }
    public var longestPauseMs: Double { longestInternalPauseMs }

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

public struct AnalysisResult: Codable, Sendable, Equatable {
    public let createdAt: Date
    public let metrics: VoiceMetrics
    public let loudnessContour: [TimePoint]
    public let pitchContour: [TimePoint]
    public let waveform: [WaveformPoint]
    public let spectrogram: SpectrogramData
    public let acousticFrames: AcousticFrameData

    public init(
        createdAt: Date = Date(),
        metrics: VoiceMetrics,
        loudnessContour: [TimePoint],
        pitchContour: [TimePoint],
        waveform: [WaveformPoint],
        spectrogram: SpectrogramData,
        acousticFrames: AcousticFrameData? = nil
    ) {
        self.createdAt = createdAt
        self.metrics = metrics
        self.loudnessContour = loudnessContour
        self.pitchContour = pitchContour
        self.waveform = waveform
        self.spectrogram = spectrogram
        self.acousticFrames = acousticFrames ?? AcousticFrameData(
            loudness: loudnessContour,
            pitch: pitchContour
        )
    }
}

public struct PracticeSession: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let audioURL: URL
    /// `nil` is retained for recordings saved by earlier app versions.
    public let source: TakeSource?
    public let result: AnalysisResult
    public let transcription: TranscriptionResult?
    public let words: [WordAnalysis]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        audioURL: URL,
        source: TakeSource? = nil,
        result: AnalysisResult,
        transcription: TranscriptionResult? = nil,
        words: [WordAnalysis] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.audioURL = audioURL
        self.source = source
        self.result = result
        self.transcription = transcription
        self.words = words
    }

    public var takeSource: TakeSource { source ?? .recorded }
}

public enum TakeSource: String, Codable, Sendable, Equatable {
    case recorded
    case importedAudio
    case importedVideo

    public var title: String {
        switch self {
        case .recorded: "Recorded here"
        case .importedAudio: "Imported audio"
        case .importedVideo: "Imported from video"
        }
    }

    public var icon: String {
        switch self {
        case .recorded: "mic.fill"
        case .importedAudio: "waveform"
        case .importedVideo: "video.fill"
        }
    }
}
