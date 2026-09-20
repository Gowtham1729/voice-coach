import Foundation

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
    self.acousticFrames =
      acousticFrames
      ?? AcousticFrameData(
        loudness: loudnessContour,
        pitch: pitchContour
      )
  }
}
