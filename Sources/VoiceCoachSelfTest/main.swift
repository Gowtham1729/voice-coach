import Foundation
import VoiceCoachCore

private struct CheckFailed: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailed(message: message) }
}

do {
    let sampleRate = 16_000.0
    let frequency = 120.0
    let duration = 1.5
    let steady = (0..<Int(sampleRate * duration)).map { index in
        Float(0.35 * sin(2 * .pi * frequency * Double(index) / sampleRate))
    }
    let steadyResult = AudioAnalyzer().analyze(samples: steady, sampleRate: sampleRate)
    try check(abs(steadyResult.metrics.duration - duration) < 0.01, "Duration calculation failed")
    try check(steadyResult.metrics.medianPitchHz != nil, "Pitch was not detected")
    try check(abs((steadyResult.metrics.medianPitchHz ?? 0) - frequency) < 2.0, "Pitch estimate was inaccurate")
    try check((steadyResult.metrics.hnrDB ?? 0) > 5, "HNR estimate was unexpectedly low")
    try check(steadyResult.metrics.cppDB != nil, "CPP was not calculated")
    try check(steadyResult.metrics.sampleRateHz == sampleRate, "Sample rate was not preserved")
    try check(!steadyResult.waveform.isEmpty, "UI waveform data was not generated")
    try check(!steadyResult.spectrogram.decibels.isEmpty, "UI spectrogram data was not generated")

    let session = PracticeSession(audioURL: URL(fileURLWithPath: "/tmp/voice-coach-self-test.wav"), result: steadyResult)
    let report = ReportFormatter.makeReport(session: session)
    try check(report.range(of: #"\d+\.\d{3,}"#, options: .regularExpression) == nil, "Structured report contains numbers with more than 2 decimal places")
    let reportData = Data(report.utf8)
    let json = try JSONSerialization.jsonObject(with: reportData) as? [String: Any]
    let expectedSections: Set<String> = ["recording", "recording_quality", "pitch", "loudness", "pauses", "voice_quality"]
    try check(Set(json?.keys.map { $0 } ?? []) == expectedSections, "Structured report sections do not match the v1 contract")
    let expectedRecording: Set<String> = ["duration_s", "active_speech_s", "sample_rate_hz"]
    let expectedQuality: Set<String> = ["noise_floor_dbfs", "snr_db", "clipping_pct"]
    let expectedPitch: Set<String> = ["median_hz", "p05_hz", "p95_hz", "range_hz", "range_semitones", "std_hz", "std_semitones", "frame_instability_pct", "contour_semitones"]
    let expectedLoudness: Set<String> = ["active_mean_dbfs", "p10_p90_range_db", "std_db", "start_dbfs", "end_dbfs", "end_minus_start_db", "contour_relative_db"]
    let expectedPauses: Set<String> = ["pause_ratio", "pause_count", "mean_pause_ms", "median_pause_ms", "longest_pause_ms"]
    let expectedVoiceQuality: Set<String> = ["hnr_db", "cpp_db"]
    try check(Set((json?["recording"] as? [String: Any])?.keys.map { $0 } ?? []) == expectedRecording, "Recording keys do not match the contract")
    try check(Set((json?["recording_quality"] as? [String: Any])?.keys.map { $0 } ?? []) == expectedQuality, "Recording-quality keys do not match the contract")
    let pitchSection = json?["pitch"] as? [String: Any]
    let loudnessSection = json?["loudness"] as? [String: Any]
    try check(Set(pitchSection?.keys.map { $0 } ?? []) == expectedPitch, "Pitch keys do not match the contract")
    try check(Set(loudnessSection?.keys.map { $0 } ?? []) == expectedLoudness, "Loudness keys do not match the contract")
    try check(Set((json?["pauses"] as? [String: Any])?.keys.map { $0 } ?? []) == expectedPauses, "Pause keys do not match the contract")
    try check(Set((json?["voice_quality"] as? [String: Any])?.keys.map { $0 } ?? []) == expectedVoiceQuality, "Voice-quality keys do not match the contract")
    try check((pitchSection?["contour_semitones"] as? [Double])?.count == 12, "Pitch contour does not contain 12 values")
    try check((loudnessSection?["contour_relative_db"] as? [Double])?.count == 12, "Loudness contour does not contain 12 values")
    let lowercaseReport = report.lowercased()
    try check(!lowercaseReport.contains("baseline"), "Structured report contains baseline data")
    try check(!lowercaseReport.contains("throat"), "Structured report contains subjective throat-effort data")
    try check(!lowercaseReport.contains("please"), "Structured report contains a coaching prompt")
    try check(!lowercaseReport.contains("waveform"), "Structured report contains UI waveform data")
    try check(!lowercaseReport.contains("spectrogram"), "Structured report contains UI spectrogram data")

    let fading = (0..<Int(sampleRate * duration)).map { index -> Float in
        let progress = Double(index) / Double(Int(sampleRate * duration) - 1)
        let amplitude = 0.7 - 0.5 * progress
        return Float(amplitude * sin(2 * .pi * 150 * Double(index) / sampleRate))
    }
    let fadingMetrics = AudioAnalyzer().analyze(samples: fading, sampleRate: sampleRate).metrics
    try check(fadingMetrics.phraseDecayDB < -5, "Phrase decay did not detect a fading signal")

    let tone = (0..<Int(sampleRate * 0.8)).map { index in
        Float(0.35 * sin(2 * .pi * frequency * Double(index) / sampleRate))
    }
    let separated = tone + [Float](repeating: 0, count: Int(sampleRate * 0.4)) + tone
    let pauseMetrics = AudioAnalyzer().analyze(samples: separated, sampleRate: sampleRate).metrics
    try check(pauseMetrics.pauseCount == 1, "Internal pause counting failed")
    try check(pauseMetrics.longestPauseMs > 250, "Pause duration was unexpectedly short")

    let silence = AudioAnalyzer().analyze(samples: [Float](repeating: 0, count: 16_000), sampleRate: 16_000)
    try check(silence.metrics.medianPitchHz == nil, "Silence incorrectly produced a pitch")

    print("VoiceCoach analysis self-test passed")
} catch {
    FileHandle.standardError.write(Data("VoiceCoach analysis self-test failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
