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

    let transcription = TranscriptionResult(
        text: "steady voice",
        words: [
            TranscriptWord(word: "steady", start: 0.10, end: 0.60),
            TranscriptWord(word: "voice", start: 0.70, end: 1.20)
        ]
    )
    let wordAnalyses = WordAcousticAnalyzer().analyze(transcription: transcription, result: steadyResult)
    try check(wordAnalyses.count == 2, "Word analysis did not preserve timestamped words")
    try check(abs((wordAnalyses[0].pitch.medianHz ?? 0) - frequency) < 2, "Word median pitch was inaccurate")
    try check(abs(wordAnalyses[0].pitch.relativeMedianSemitones ?? 99) < 0.1, "Relative word pitch did not use the recording median")
    try check(wordAnalyses[0].loudness.relativeMeanDB != nil, "Relative word loudness was not calculated")

    let measuredTimes = [0.10, 0.20, 0.30, 0.40]
    let octaveResult = AnalysisResult(
        metrics: steadyResult.metrics,
        loudnessContour: steadyResult.loudnessContour,
        pitchContour: steadyResult.pitchContour,
        waveform: steadyResult.waveform,
        spectrogram: steadyResult.spectrogram,
        acousticFrames: AcousticFrameData(
            loudness: measuredTimes.map {
                TimePoint(time: $0, value: steadyResult.metrics.meanLoudnessDBFS + 3)
            },
            pitch: measuredTimes.map { TimePoint(time: $0, value: frequency * 2) }
        )
    )
    let octaveWord = WordAcousticAnalyzer().analyze(
        transcription: TranscriptionResult(
            text: "higher",
            words: [TranscriptWord(word: "higher", start: 0.05, end: 0.45)]
        ),
        result: octaveResult
    )[0]
    let expectedRelativePitch = 12 * log2(
        (frequency * 2) / (steadyResult.metrics.medianPitchHz ?? frequency)
    )
    try check(abs((octaveWord.pitch.relativeMedianSemitones ?? 0) - expectedRelativePitch) < 0.001, "Relative pitch did not use 12 * log2(word / recording median)")
    try check(abs((octaveWord.loudness.relativeMeanDB ?? 0) - 3) < 0.01, "Relative loudness did not use the active-speech mean")

    let session = PracticeSession(
        audioURL: URL(fileURLWithPath: "/tmp/voice-coach-self-test.wav"),
        result: steadyResult,
        transcription: transcription,
        words: wordAnalyses
    )
    let report = ReportFormatter.makeReport(session: session)
    let compactReport = ReportFormatter.makeCompactReport(session: session)
    try check(report.range(of: #"\d+\.\d{3,}"#, options: .regularExpression) == nil, "Structured report contains numbers with more than 2 decimal places")
    let reportData = Data(report.utf8)
    let json = try JSONSerialization.jsonObject(with: reportData) as? [String: Any]
    let expectedSections: Set<String> = ["recording", "recording_quality", "pitch", "loudness", "pauses", "voice_quality", "transcription", "words"]
    try check(Set(json?.keys.map { $0 } ?? []) == expectedSections, "Structured report did not preserve V1 sections plus transcription and words")
    let compactJSON = try JSONSerialization.jsonObject(with: Data(compactReport.utf8)) as? [String: Any]
    let expectedCompactSections: Set<String> = ["recording", "recording_quality", "pitch", "loudness", "pauses", "voice_quality"]
    try check(Set(compactJSON?.keys.map { $0 } ?? []) == expectedCompactSections, "Compact report did not preserve the original six sections")
    try check(!compactReport.contains("transcription") && !compactReport.contains("words"), "Compact report contains word-level data")
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
    try check((json?["transcription"] as? [String: Any])?["text"] as? String == "steady voice", "Transcript text was not exported")
    let exportedWords = json?["words"] as? [[String: Any]]
    try check(exportedWords?.count == 2, "Timestamped words were not exported")
    let expectedWordKeys: Set<String> = ["word", "start_s", "end_s", "duration_ms", "pitch", "loudness"]
    try check(Set(exportedWords?.first?.keys.map { $0 } ?? []) == expectedWordKeys, "Word report keys do not match the contract")
    let expectedWordPitchKeys: Set<String> = ["median_hz", "relative_median_semitones", "range_semitones", "start_to_end_semitones"]
    let expectedWordLoudnessKeys: Set<String> = ["relative_mean_db", "start_to_end_db"]
    try check(Set((exportedWords?.first?["pitch"] as? [String: Any])?.keys.map { $0 } ?? []) == expectedWordPitchKeys, "Word pitch keys do not match the contract")
    try check(Set((exportedWords?.first?["loudness"] as? [String: Any])?.keys.map { $0 } ?? []) == expectedWordLoudnessKeys, "Word loudness keys do not match the contract")
    try check((pitchSection?["contour_semitones"] as? [Double])?.count == 12, "Pitch contour does not contain 12 values")
    try check((loudnessSection?["contour_relative_db"] as? [Double])?.count == 12, "Loudness contour does not contain 12 values")
    let lowercaseReport = report.lowercased()
    try check(!lowercaseReport.contains("baseline"), "Structured report contains baseline data")
    try check(!lowercaseReport.contains("throat"), "Structured report contains subjective throat-effort data")
    try check(!lowercaseReport.contains("please"), "Structured report contains a coaching prompt")
    try check(!lowercaseReport.contains("waveform"), "Structured report contains UI waveform data")
    try check(!lowercaseReport.contains("spectrogram"), "Structured report contains UI spectrogram data")
    try check(!lowercaseReport.contains("acousticframes"), "Structured report contains dense acoustic frames")

    let parserFixture = Data(#"{"result":{"text":"I really tried","words":[{"word":"I","start":0.1,"end":0.22},{"word":"really","start":0.55,"end":0.94,"confidence":0.97},{"word":"tried","start":1.0,"duration":0.3}]}}"#.utf8)
    let parsed = try NemoSpeechTranscriber.parseOutput(parserFixture)
    try check(parsed.text == "I really tried", "NeMo JSON transcript parsing failed")
    try check(parsed.words.count == 3, "NeMo JSON word parsing failed")
    try check(abs(parsed.words[1].start - 0.55) < 0.001 && abs(parsed.words[1].end - 0.94) < 0.001, "NeMo word timestamps were not preserved")
    try check(abs(parsed.words[2].end - 1.3) < 0.001, "NeMo duration fallback was not converted to an end time")

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
    let silentWords = WordAcousticAnalyzer().analyze(
        transcription: TranscriptionResult(
            text: "quiet",
            words: [TranscriptWord(word: "quiet", start: 0.1, end: 0.5)]
        ),
        result: silence
    )
    try check(silentWords[0].pitch.medianHz == nil, "Unvoiced word invented a median pitch")
    try check(silentWords[0].pitch.relativeMedianSemitones == nil, "Unvoiced word invented a relative pitch")
    let silentSession = PracticeSession(
        audioURL: URL(fileURLWithPath: "/tmp/voice-coach-silence.wav"),
        result: silence,
        transcription: TranscriptionResult(text: "quiet", words: []),
        words: silentWords
    )
    let silentReportData = Data(ReportFormatter.makeReport(session: silentSession).utf8)
    let silentJSON = try JSONSerialization.jsonObject(with: silentReportData) as? [String: Any]
    let silentPitch = ((silentJSON?["words"] as? [[String: Any]])?.first?["pitch"] as? [String: Any])
    try check(silentPitch?["median_hz"] is NSNull, "Missing word pitch was not exported as null")

    if let argumentIndex = CommandLine.arguments.firstIndex(of: "--transcribe"),
       CommandLine.arguments.indices.contains(argumentIndex + 1) {
        let audioURL = URL(fileURLWithPath: CommandLine.arguments[argumentIndex + 1])
        let liveResult = try AudioAnalyzer().analyze(url: audioURL)
        let liveTranscription = try NemoSpeechTranscriber().transcribe(url: audioURL)
        let liveWords = WordAcousticAnalyzer().analyze(
            transcription: liveTranscription,
            result: liveResult
        )
        try check(!liveTranscription.text.isEmpty, "Live Parakeet smoke test returned an empty transcript")
        try check(!liveWords.isEmpty, "Live Parakeet smoke test returned no timestamped words")
        let liveSession = PracticeSession(
            audioURL: audioURL,
            result: liveResult,
            transcription: liveTranscription,
            words: liveWords
        )
        print(ReportFormatter.makeReport(session: liveSession))
    }

    print("VoiceCoach analysis self-test passed")
} catch {
    FileHandle.standardError.write(Data("VoiceCoach analysis self-test failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
