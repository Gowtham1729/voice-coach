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
