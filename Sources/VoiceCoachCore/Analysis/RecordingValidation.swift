import Foundation

/// Save-time checks, separate from analysis so silent fixtures remain analyzable.
public enum RecordingValidation {
  public static func validateAudio(_ result: AnalysisResult) throws {
    guard result.metrics.duration > 0, !result.waveform.isEmpty else {
      throw AnalysisError.emptyRecording
    }
    // Match the existing Mac audio capture floor. Do not require pitch or an ASR result:
    // quiet speech and unvoiced sounds can still be valid recordings.
    guard result.waveform.contains(where: {
      abs($0.minimum) > 1e-4 || abs($0.maximum) > 1e-4
    }) else { throw AnalysisError.silentRecording }
  }

  public static func validateTranscription(_ result: TranscriptionResult) throws {
    guard result.hasRecognizedSpeech else { throw TranscriptionError.noSpeechRecognized }
  }
}
