import Foundation

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
