import Foundation

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
  case systemAudio

  public var title: String {
    switch self {
    case .recorded: "Recorded here"
    case .importedAudio: "Imported audio"
    case .importedVideo: "Imported from video"
    case .systemAudio: "Mac audio reference"
    }
  }

  public var icon: String {
    switch self {
    case .recorded: "mic.fill"
    case .importedAudio: "waveform"
    case .importedVideo: "video.fill"
    case .systemAudio: "speaker.wave.2.fill"
    }
  }
}
