import Foundation
import VoiceCoachCore

#if canImport(AVFoundation)
  import AVFoundation
#endif

private struct CheckFailed: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  if !condition() { throw CheckFailed(message: message) }
}

#if canImport(AVFoundation)
  private func writeTestWAV(samples: [Float], sampleRate: Double, to url: URL) throws {
    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
      ),
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
      let channel = buffer.floatChannelData?.pointee
    else { throw CheckFailed(message: "Could not create import-test audio") }

    buffer.frameLength = AVAudioFrameCount(samples.count)
    for (index, sample) in samples.enumerated() { channel[index] = sample }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
  }

  private func verifyAudioImport(samples: [Float], sampleRate: Double) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "VoiceCoachImportTest-\(UUID().uuidString)", isDirectory: true)
    let sourceURL = directory.appendingPathComponent("phone-recording.wav")
    let importedURL = directory.appendingPathComponent("prepared.wav")
    let excerptURL = directory.appendingPathComponent("excerpt.wav")
    defer { try? FileManager.default.removeItem(at: directory) }

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try writeTestWAV(samples: samples, sampleRate: sampleRate, to: sourceURL)
    try await AudioImportService.prepareAudio(from: sourceURL, to: importedURL)

    try check(
      FileManager.default.fileExists(atPath: importedURL.path),
      "Imported audio was not written locally")
    try check(
      AudioImportService.source(for: sourceURL) == .importedAudio, "Audio source was not identified"
    )
    try check(
      AudioImportService.source(for: URL(fileURLWithPath: "/tmp/reference.mov")) == .importedVideo,
      "Video source was not identified")
    let importedAnalysis = try AudioAnalyzer().analyze(url: importedURL)
    try check(importedAnalysis.metrics.duration > 1, "Prepared import could not be analyzed")
    let overview = try AudioImportService.waveform(from: importedURL)
    try check(
      overview.peaks.count >= 300 && overview.peaks.contains(where: { $0 > 0 }),
      "Reference waveform preparation failed")
    let explicitOverview = try AudioImportService.waveform(from: importedURL, buckets: 180)
    try check(
      explicitOverview.peaks.count == 180,
      "Explicit waveform resolution changed")
    try AudioImportService.trimAudio(from: importedURL, to: excerptURL, start: 0.2, end: 1.4)
    let excerpt = try AudioAnalyzer().analyze(url: excerptURL)
    let excerptFile = try AVAudioFile(forReading: excerptURL)
    let probe = AVAudioPCMBuffer(
      pcmFormat: excerptFile.processingFormat, frameCapacity: AVAudioFrameCount(excerptFile.length))!
    try excerptFile.read(into: probe)
    try check(
      abs(excerpt.metrics.duration - 1.2) < 0.01,
      "Reference excerpt was not trimmed precisely (source \(importedAnalysis.metrics.duration)s, file \(excerptFile.length) frames at \(excerptFile.processingFormat.sampleRate) Hz, decoded \(excerpt.metrics.duration)s, buffer \(probe.frameLength), position \(excerptFile.framePosition))"
    )
    do {
      try AudioImportService.trimAudio(
        from: importedURL, to: directory.appendingPathComponent("invalid.wav"), start: 0.7, end: 0.8
      )
      throw CheckFailed(message: "Invalid short reference excerpt was accepted")
    } catch AudioImportError.invalidExcerpt {}
  }
#endif

do {
  // print("Args: \(CommandLine.arguments)")

  let sampleRate = 16_000.0
  let frequency = 120.0
  let duration = 1.5
  let steady = (0..<Int(sampleRate * duration)).map { index in
    Float(0.35 * sin(2 * .pi * frequency * Double(index) / sampleRate))
  }
  #if canImport(AVFoundation)
    try await verifyAudioImport(samples: steady, sampleRate: sampleRate)
  #else
    try check(
      AudioImportService.source(for: URL(fileURLWithPath: "/tmp/phone-recording.wav"))
        == .importedAudio, "Audio source was not identified")
    try check(
      AudioImportService.source(for: URL(fileURLWithPath: "/tmp/reference.mov")) == .importedVideo,
      "Video source was not identified")
  #endif
  let steadyResult = AudioAnalyzer().analyze(samples: steady, sampleRate: sampleRate)
  try check(abs(steadyResult.metrics.duration - duration) < 0.01, "Duration calculation failed")
  try check(steadyResult.metrics.medianPitchHz != nil, "Pitch was not detected")
  try check(
    abs((steadyResult.metrics.medianPitchHz ?? 0) - frequency) < 2.0,
    "Pitch estimate was inaccurate")
  try check((steadyResult.metrics.hnrDB ?? 0) > 5, "HNR estimate was unexpectedly low")
  try check(steadyResult.metrics.cppDB != nil, "CPP was not calculated")
  try check(steadyResult.metrics.sampleRateHz == sampleRate, "Sample rate was not preserved")
  try check(!steadyResult.waveform.isEmpty, "UI waveform data was not generated")
  try check(!steadyResult.spectrogram.decibels.isEmpty, "UI spectrogram data was not generated")

  let transcription = TranscriptionResult(
    text: "steady voice",
    words: [
      TranscriptWord(word: "steady", start: 0.10, end: 0.60),
      TranscriptWord(word: "voice", start: 0.70, end: 1.20),
    ]
  )
  let wordAnalyses = WordAcousticAnalyzer().analyze(
    transcription: transcription, result: steadyResult)
  try check(wordAnalyses.count == 2, "Word analysis did not preserve timestamped words")
  try check(
    abs((wordAnalyses[0].pitch.medianHz ?? 0) - frequency) < 2, "Word median pitch was inaccurate")
  try check(
    abs(wordAnalyses[0].pitch.relativeMedianSemitones ?? 99) < 0.1,
    "Relative word pitch did not use the recording median")
  try check(
    wordAnalyses[0].loudness.relativeMeanDB != nil, "Relative word loudness was not calculated")

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
  let expectedRelativePitch =
    12
    * log2(
      (frequency * 2) / (steadyResult.metrics.medianPitchHz ?? frequency)
    )
  try check(
    abs((octaveWord.pitch.relativeMedianSemitones ?? 0) - expectedRelativePitch) < 0.001,
    "Relative pitch did not use 12 * log2(word / recording median)")
  try check(
    abs((octaveWord.loudness.relativeMeanDB ?? 0) - 3) < 0.01,
    "Relative loudness did not use the active-speech mean")

  let session = PracticeSession(
    audioURL: URL(fileURLWithPath: "/tmp/voice-coach-self-test.wav"),
    result: steadyResult,
    transcription: transcription,
    words: wordAnalyses
  )
  let referenceWords = [
    TranscriptWord(word: "Hello,", start: 0.10, end: 0.30),
    TranscriptWord(word: "this", start: 0.32, end: 0.50),
    TranscriptWord(word: "voice.", start: 0.52, end: 0.80),
  ]
  let attemptWords = [
    TranscriptWord(word: "hello", start: 0.10, end: 0.30),
    TranscriptWord(word: "this", start: 0.32, end: 0.50),
    TranscriptWord(word: "voice", start: 0.90, end: 1.18),
  ]
  let phraseSamples = (0..<Int(sampleRate * 1.5)).map { index -> Float in
    let time = Double(index) / sampleRate
    let voiced =
      (0.1..<0.3).contains(time) || (0.32..<0.5).contains(time) || (0.52..<1.2).contains(time)
    return voiced ? Float(0.3 * sin(2 * .pi * 150 * time)) : 0.0001
  }
  let mimicResult = AudioAnalyzer().analyze(samples: phraseSamples, sampleRate: sampleRate)
  func mimicTake(_ words: [TranscriptWord]) -> PracticeSession {
    let transcript = TranscriptionResult(
      text: words.map(\.word).joined(separator: " "), words: words)
    return PracticeSession(
      audioURL: URL(fileURLWithPath: "/tmp/mimic-fixture.wav"),
      result: mimicResult, transcription: transcript,
      words: WordAcousticAnalyzer().analyze(transcription: transcript, result: mimicResult)
    )
  }
  let mimicReference = mimicTake(referenceWords)
  let mimicAttempt = mimicTake(attemptWords)
  let comparison = MimicComparison.compare(reference: mimicReference, attempt: mimicAttempt)
  try check(
    comparison.correspondenceReliable && comparison.pairs.count == 3,
    "Mimic word alignment failed (pairs \(comparison.pairs.count), SNR \(mimicResult.metrics.snrDB), clipping \(mimicResult.metrics.clippingPercent))"
  )
  try check(comparison.status == .ok, "Reliable mimic alignment did not report status ok")
  let mismatched = mimicTake([
    TranscriptWord(word: "unrelated", start: 0.1, end: 0.3),
    TranscriptWord(word: "phrasing", start: 0.4, end: 0.6),
  ])
  let uncertain = MimicComparison.compare(reference: mimicReference, attempt: mismatched)
  try check(
    !uncertain.correspondenceReliable,
    "Mimic inferred reliable correspondence from mismatched wording")
  try check(
    uncertain.status == .lowCoverage, "Mismatched wording did not report low_coverage status")

  let mimicCompareJSON = ReportFormatter.makeMimicCompareReport(
    reference: mimicReference,
    attempt: mimicAttempt,
    practiceStyle: "Listen & Repeat",
    comparison: comparison
  )
  let mimicCompareObject =
    try JSONSerialization.jsonObject(with: Data(mimicCompareJSON.utf8)) as? [String: Any]
  let expectedMimicKeys: Set<String> = [
    "schema_version", "practice_style", "reference", "attempt",
    "reference_transcript", "attempt_transcript", "alignment",
  ]
  try check(
    Set(mimicCompareObject?.keys.map { $0 } ?? []) == expectedMimicKeys,
    "Mimic compare report keys do not match the contract")
  try check(
    mimicCompareObject?["schema_version"] as? Int == 1, "Mimic compare schema_version missing")
  try check(
    mimicCompareObject?["practice_style"] as? String == "Listen & Repeat",
    "Mimic compare practice_style missing")
  let mimicAlignment = mimicCompareObject?["alignment"] as? [String: Any]
  try check(
    mimicAlignment?["reliable"] as? Bool == true,
    "Reliable mimic compare omitted alignment.reliable")
  try check(
    mimicAlignment?["status"] as? String == "ok", "Reliable mimic compare omitted alignment.status")
  try check(
    mimicAlignment?["matched_word_count"] as? Int == 3,
    "Reliable mimic compare matched_word_count mismatch")
  let mimicAlignedWords = mimicAlignment?["words"] as? [[String: Any]]
  try check(mimicAlignedWords?.count == 3, "Reliable mimic compare omitted alignment words")
  let expectedAlignWordKeys: Set<String> = [
    "word", "ref_start_s", "attempt_start_s", "ref_duration_ms", "attempt_duration_ms",
    "duration_delta_ms", "start_delta_ms", "ref_pitch_st", "attempt_pitch_st", "pitch_delta_st",
    "ref_energy_db", "attempt_energy_db", "energy_delta_db",
  ]
  try check(
    Set(mimicAlignedWords?.first?.keys.map { $0 } ?? []) == expectedAlignWordKeys,
    "Mimic alignment word keys do not match the contract")
  let mimicRefSection = mimicCompareObject?["reference"] as? [String: Any]
  let mimicAttemptSection = mimicCompareObject?["attempt"] as? [String: Any]
  try check(
    mimicRefSection?["words"] == nil && mimicAttemptSection?["words"] == nil,
    "Mimic compare embedded full word arrays")
  try check(
    mimicRefSection?["transcription"] == nil && mimicAttemptSection?["transcription"] == nil,
    "Mimic compare embedded nested transcription objects")
  let lowercaseMimicCompare = mimicCompareJSON.lowercased()
  try check(
    !lowercaseMimicCompare.contains("baseline"), "Mimic compare report contains baseline data")
  try check(
    !lowercaseMimicCompare.contains("throat"),
    "Mimic compare report contains subjective throat-effort data")
  try check(
    !lowercaseMimicCompare.contains("please"), "Mimic compare report contains a coaching prompt")
  try check(
    !lowercaseMimicCompare.contains("cpp_db"),
    "Mimic compare report contains cpp_db when it should be excluded")
  try check(
    mimicCompareJSON.utf8.count < 50_000,
    "Mimic compare fixture payload exceeded size budget (\(mimicCompareJSON.utf8.count) bytes)")

  let uncertainCompareJSON = ReportFormatter.makeMimicCompareReport(
    reference: mimicReference,
    attempt: mismatched,
    practiceStyle: "Speak Along",
    comparison: uncertain
  )
  let uncertainCompareObject =
    try JSONSerialization.jsonObject(with: Data(uncertainCompareJSON.utf8)) as? [String: Any]
  let uncertainAlignment = uncertainCompareObject?["alignment"] as? [String: Any]
  try check(
    uncertainAlignment?["reliable"] as? Bool == false, "Unreliable mimic compare claimed reliable")
  try check(
    uncertainAlignment?["status"] as? String == "low_coverage",
    "Unreliable mimic compare status mismatch")
  try check(
    uncertainAlignment?["words"] == nil, "Unreliable mimic compare still included alignment words")

  let noTranscriptAttempt = PracticeSession(
    audioURL: URL(fileURLWithPath: "/tmp/mimic-no-asr.wav"),
    result: mimicResult, transcription: nil, words: []
  )
  let missingASR = MimicComparison.compare(reference: mimicReference, attempt: noTranscriptAttempt)
  try check(
    missingASR.status == .missingTranscript && !missingASR.correspondenceReliable,
    "Missing ASR did not report missing_transcript")
  let missingASRJSON = ReportFormatter.makeMimicCompareReport(
    reference: mimicReference, attempt: noTranscriptAttempt, practiceStyle: "Listen & Repeat",
    comparison: missingASR
  )
  let missingASRObject =
    try JSONSerialization.jsonObject(with: Data(missingASRJSON.utf8)) as? [String: Any]
  try check(
    (missingASRObject?["alignment"] as? [String: Any])?["words"] == nil,
    "Missing-ASR compare included alignment words")

  let legacyRoundTrip = try JSONDecoder().decode(
    PracticeSession.self, from: JSONEncoder().encode(session))
  try check(
    legacyRoundTrip.takeSource == .recorded,
    "Saved recordings without a source were not treated as microphone takes")
  let importedSession = PracticeSession(
    audioURL: URL(fileURLWithPath: "/tmp/voice-coach-imported.wav"),
    source: .importedVideo,
    result: steadyResult
  )
  let importedRoundTrip = try JSONDecoder().decode(
    PracticeSession.self, from: JSONEncoder().encode(importedSession))
  try check(
    importedRoundTrip.takeSource == .importedVideo, "Imported video source was not preserved")
  let systemAudioSession = PracticeSession(
    audioURL: URL(fileURLWithPath: "/tmp/voice-coach-system.wav"),
    source: .systemAudio,
    result: steadyResult
  )
  let systemAudioRoundTrip = try JSONDecoder().decode(
    PracticeSession.self, from: JSONEncoder().encode(systemAudioSession))
  try check(
    systemAudioRoundTrip.takeSource == .systemAudio, "System audio source was not preserved")
  try check(
    TakeSource.systemAudio.title.contains("Mac"), "System audio reference source title drifted")
  let report = ReportFormatter.makeReport(session: session)
  let compactReport = ReportFormatter.makeCompactReport(session: session)
  try check(
    report.range(of: #"\d+\.\d{3,}"#, options: .regularExpression) == nil,
    "Structured report contains numbers with more than 2 decimal places")
  let reportData = Data(report.utf8)
  let json = try JSONSerialization.jsonObject(with: reportData) as? [String: Any]
  let expectedSections: Set<String> = [
    "recording", "recording_quality", "pitch", "loudness", "pauses", "voice_quality",
    "transcription", "words",
  ]
  try check(
    Set(json?.keys.map { $0 } ?? []) == expectedSections,
    "Structured report did not preserve V1 sections plus transcription and words")
  let compactJSON =
    try JSONSerialization.jsonObject(with: Data(compactReport.utf8)) as? [String: Any]
  let expectedCompactSections: Set<String> = [
    "recording", "recording_quality", "pitch", "loudness", "pauses", "voice_quality",
  ]
  try check(
    Set(compactJSON?.keys.map { $0 } ?? []) == expectedCompactSections,
    "Compact report did not preserve the original six sections")
  try check(
    !compactReport.contains("transcription") && !compactReport.contains("words"),
    "Compact report contains word-level data")
  let expectedRecording: Set<String> = ["duration_s", "active_speech_s", "sample_rate_hz"]
  let expectedQuality: Set<String> = ["noise_floor_dbfs", "snr_db", "clipping_pct"]
  let expectedPitch: Set<String> = [
    "median_hz", "p05_hz", "p95_hz", "range_hz", "range_semitones", "std_hz", "std_semitones",
    "frame_instability_pct", "contour_semitones",
  ]
  let expectedLoudness: Set<String> = [
    "active_mean_dbfs", "p10_p90_range_db", "std_db", "start_dbfs", "end_dbfs",
    "end_minus_start_db", "contour_relative_db",
  ]
  let expectedPauses: Set<String> = [
    "non_speech_ratio", "internal_pause_count", "internal_pause_total_ms", "mean_internal_pause_ms",
    "median_internal_pause_ms", "longest_internal_pause_ms", "leading_silence_ms",
    "trailing_silence_ms",
  ]
  let expectedVoiceQuality: Set<String> = ["hnr_db"]
  try check(
    Set((json?["recording"] as? [String: Any])?.keys.map { $0 } ?? []) == expectedRecording,
    "Recording keys do not match the contract")
  try check(
    Set((json?["recording_quality"] as? [String: Any])?.keys.map { $0 } ?? []) == expectedQuality,
    "Recording-quality keys do not match the contract")
  let pitchSection = json?["pitch"] as? [String: Any]
  let loudnessSection = json?["loudness"] as? [String: Any]
  try check(
    Set(pitchSection?.keys.map { $0 } ?? []) == expectedPitch,
    "Pitch keys do not match the contract")
  try check(
    Set(loudnessSection?.keys.map { $0 } ?? []) == expectedLoudness,
    "Loudness keys do not match the contract")
  try check(
    Set((json?["pauses"] as? [String: Any])?.keys.map { $0 } ?? []) == expectedPauses,
    "Pause keys do not match the contract")
  try check(
    Set((json?["voice_quality"] as? [String: Any])?.keys.map { $0 } ?? []) == expectedVoiceQuality,
    "Voice-quality keys do not match the contract")
  try check(
    (json?["transcription"] as? [String: Any])?["text"] as? String == "steady voice",
    "Transcript text was not exported")
  let exportedWords = json?["words"] as? [[String: Any]]
  try check(exportedWords?.count == 2, "Timestamped words were not exported")
  let expectedWordKeys: Set<String> = [
    "word", "start_s", "end_s", "duration_ms", "pitch", "loudness",
  ]
  try check(
    Set(exportedWords?.first?.keys.map { $0 } ?? []) == expectedWordKeys,
    "Word report keys do not match the contract")
  let expectedWordPitchKeys: Set<String> = [
    "median_hz", "relative_median_semitones", "range_semitones", "start_to_end_semitones",
    "valid_pitch_frames", "pitch_coverage",
  ]
  let expectedWordLoudnessKeys: Set<String> = [
    "relative_mean_db", "start_to_end_db", "active_frame_coverage",
  ]
  try check(
    Set((exportedWords?.first?["pitch"] as? [String: Any])?.keys.map { $0 } ?? [])
      == expectedWordPitchKeys, "Word pitch keys do not match the contract")
  try check(
    Set((exportedWords?.first?["loudness"] as? [String: Any])?.keys.map { $0 } ?? [])
      == expectedWordLoudnessKeys, "Word loudness keys do not match the contract")
  try check(
    (pitchSection?["contour_semitones"] as? [Double])?.count == 24,
    "Pitch contour does not contain 24 values")
  try check(
    (loudnessSection?["contour_relative_db"] as? [Double])?.count == 24,
    "Loudness contour does not contain 24 values")
  let lowercaseReport = report.lowercased()
  try check(!lowercaseReport.contains("baseline"), "Structured report contains baseline data")
  try check(
    !lowercaseReport.contains("throat"), "Structured report contains subjective throat-effort data")
  try check(!lowercaseReport.contains("please"), "Structured report contains a coaching prompt")
  try check(!lowercaseReport.contains("waveform"), "Structured report contains UI waveform data")
  try check(
    !lowercaseReport.contains("spectrogram"), "Structured report contains UI spectrogram data")
  try check(
    !lowercaseReport.contains("acousticframes"), "Structured report contains dense acoustic frames")
  try check(
    !lowercaseReport.contains("cpp_db"),
    "Structured report contains cpp_db when it should be excluded")
  try check(
    !compactReport.contains("cpp_db"), "Compact report contains cpp_db when it should be excluded")

  // Keep word-level JSON responsive for long takes (copy/export path).
  let emptyPitch = WordPitchMetrics(
    medianHz: nil, relativeMedianSemitones: nil, rangeSemitones: nil, startToEndSemitones: nil
  )
  let emptyLoudness = WordLoudnessMetrics(relativeMeanDB: nil, startToEndDB: nil)
  let longWords = (0..<4_000).map { index in
    TranscriptWord(word: "w\(index)", start: Double(index) * 0.12, end: Double(index) * 0.12 + 0.1)
  }
  let longSession = PracticeSession(
    audioURL: URL(fileURLWithPath: "/tmp/voice-coach-long-take.wav"),
    result: steadyResult,
    transcription: TranscriptionResult(
      text: longWords.map(\.word).joined(separator: " "), words: longWords),
    words: longWords.map {
      WordAnalysis(
        word: $0.word, start: $0.start, end: $0.end, pitch: emptyPitch, loudness: emptyLoudness)
    }
  )
  let longReportStarted = Date()
  let longReport = ReportFormatter.makeReport(session: longSession)
  let longReportElapsed = Date().timeIntervalSince(longReportStarted)
  try check(longReportElapsed < 2.0, "Word-level report for 4000 words took \(longReportElapsed)s")
  try check(longReport.contains("\"w3999\""), "Long-take report omitted the final word")
  let longReportJSON =
    try JSONSerialization.jsonObject(with: Data(longReport.utf8)) as? [String: Any]
  try check(longReportJSON?["words"] is [Any], "Long-take report words array missing")
  print(
    String(
      format: "Long-take report (4000 words): %.3fs, %d bytes", longReportElapsed,
      longReport.utf8.count))

  let parserFixture = Data(
    #"{"result":{"text":"I really tried","words":[{"word":"I","start":0.1,"end":0.22},{"word":"really","start":0.55,"end":0.94,"confidence":0.97},{"word":"tried","start":1.0,"duration":0.3}]}}"#
      .utf8)
  let parsed = try NemoSpeechTranscriber.parseOutput(parserFixture)
  try check(parsed.text == "I really tried", "NeMo JSON transcript parsing failed")
  try check(parsed.words.count == 3, "NeMo JSON word parsing failed")
  try check(
    abs(parsed.words[1].start - 0.55) < 0.001 && abs(parsed.words[1].end - 0.94) < 0.001,
    "NeMo word timestamps were not preserved")
  try check(
    abs(parsed.words[2].end - 1.3) < 0.001,
    "NeMo duration fallback was not converted to an end time")

  let unavailableCopy = TranscriptionError.runtimeUnavailable.errorDescription ?? ""
  try check(
    unavailableCopy.contains("Settings"), "Runtime-unavailable copy should point users to Settings")
  try check(
    TranscriptionEnginePreference.default == .system,
    "Default transcription engine should be System")
  try check(
    TranscriptionEnginePreference.system.title.contains("Apple"), "System engine title drifted")
  #if canImport(Speech)
    let appleAvailable = await AppleSpeechTranscriber.isAvailable()
    print("Apple SpeechTranscriber available: \(appleAvailable)")
    let systemStatus = await AppleSpeechTranscriber.currentStatus()
    print("Apple system transcription status: \(systemStatus)")
  #endif
  let managed = try TranscriptionSetupService.managedExecutableURL()
  try check(
    managed.path.contains("/VoiceCoach/Transcription/NeMoSpeech/bin/nemo-speech"),
    "Managed runtime path drifted")
  let modelCache = try TranscriptionSetupService.modelRepositoryCacheURL()
  try check(
    modelCache.path.contains("/NeMoSpeech/models/\(NemoSpeechTranscriber.defaultModel)"),
    "Model cache path drifted")
  _ = TranscriptionSetupService.currentStatus()

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
  try check(pauseMetrics.internalPauseCount == 1, "Internal pause counting failed")
  try check(pauseMetrics.longestInternalPauseMs > 250, "Pause duration was unexpectedly short")
  try check(
    pauseMetrics.internalPauseTotalMs > 250, "Total internal pause duration was unexpectedly short")
  try check(pauseMetrics.nonSpeechRatio > 0.15, "Non-speech ratio was unexpectedly low")

  // Leading and trailing silence test
  let leadingSilence = [Float](repeating: 0, count: Int(sampleRate * 0.3))
  let trailingSilence = [Float](repeating: 0, count: Int(sampleRate * 0.4))
  let paddedTone = leadingSilence + tone + trailingSilence
  let silenceMetrics = AudioAnalyzer().analyze(samples: paddedTone, sampleRate: sampleRate).metrics
  try check(silenceMetrics.leadingSilenceMs >= 250, "Leading silence was not detected")
  try check(silenceMetrics.trailingSilenceMs >= 350, "Trailing silence was not detected")
  try check(
    silenceMetrics.internalPauseCount == 0,
    "False internal pause detected in leading/trailing silence")

  let silence = AudioAnalyzer().analyze(
    samples: [Float](repeating: 0, count: 16_000), sampleRate: 16_000)
  try check(silence.metrics.medianPitchHz == nil, "Silence incorrectly produced a pitch")
  let silentWords = WordAcousticAnalyzer().analyze(
    transcription: TranscriptionResult(
      text: "quiet",
      words: [TranscriptWord(word: "quiet", start: 0.1, end: 0.5)]
    ),
    result: silence
  )
  try check(silentWords[0].pitch.medianHz == nil, "Unvoiced word invented a median pitch")
  try check(
    silentWords[0].pitch.relativeMedianSemitones == nil, "Unvoiced word invented a relative pitch")
  try check(silentWords[0].pitch.validPitchFrames == 0, "Silent word reported valid pitch frames")
  try check(silentWords[0].pitch.pitchCoverage == 0, "Silent word reported pitch coverage")
  try check(
    silentWords[0].loudness.activeFrameCoverage == 0, "Silent word reported active frame coverage")
  try check(silentWords[0].loudness.relativeMeanDB == nil, "Silent word invented loudness dB")
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
  try check(silentPitch?["valid_pitch_frames"] as? Int == 0, "Missing pitch frame count was not 0")
  try check(
    (silentPitch?["pitch_coverage"] as? Double ?? 1) == 0, "Missing pitch coverage was not 0")

  // Robustness test: Low pitch coverage returns null metrics without inventing values
  let lowCoverageTimes = (0..<10).map { 0.10 + Double($0) * 0.05 }
  let lowCoverageResult = AnalysisResult(
    metrics: steadyResult.metrics,
    loudnessContour: steadyResult.loudnessContour,
    pitchContour: steadyResult.pitchContour,
    waveform: steadyResult.waveform,
    spectrogram: steadyResult.spectrogram,
    acousticFrames: AcousticFrameData(
      loudness: lowCoverageTimes.map {
        TimePoint(time: $0, value: steadyResult.metrics.meanLoudnessDBFS)
      },
      // Only 1 valid frame out of 10: coverage 0.10 (< 0.20).
      pitch: [TimePoint(time: 0.15, value: 200.0)]
    )
  )
  let lowCoverageWord = WordAcousticAnalyzer().analyze(
    transcription: TranscriptionResult(
      text: "whisper",
      words: [TranscriptWord(word: "whisper", start: 0.08, end: 0.60)]
    ),
    result: lowCoverageResult
  )[0]
  try check(lowCoverageWord.pitch.validPitchFrames == 1, "Valid pitch frame count was wrong")
  try check(
    abs(lowCoverageWord.pitch.pitchCoverage - 0.10) < 0.02,
    "Pitch coverage calculation was inaccurate")
  try check(lowCoverageWord.pitch.medianHz == nil, "Low coverage should return null for median Hz")
  try check(
    lowCoverageWord.pitch.rangeSemitones == nil,
    "Low coverage should return null for range semitones")
  try check(
    lowCoverageWord.pitch.startToEndSemitones == nil,
    "Low coverage should return null for start to end semitones")

  // Robustness test: P10-P90 pitch range ignores an octave jump spike
  let jumpTimes = (0..<10).map { 0.10 + Double($0) * 0.05 }
  var jumpPitches = [Double](repeating: 200.0, count: 9)
  jumpPitches.append(400.0)  // Single octave spike at the end
  let jumpResult = AnalysisResult(
    metrics: steadyResult.metrics,
    loudnessContour: steadyResult.loudnessContour,
    pitchContour: steadyResult.pitchContour,
    waveform: steadyResult.waveform,
    spectrogram: steadyResult.spectrogram,
    acousticFrames: AcousticFrameData(
      loudness: jumpTimes.map { TimePoint(time: $0, value: steadyResult.metrics.meanLoudnessDBFS) },
      pitch: zip(jumpTimes, jumpPitches).map { TimePoint(time: $0, value: $1) }
    )
  )
  let jumpWord = WordAcousticAnalyzer().analyze(
    transcription: TranscriptionResult(
      text: "steady_jump",
      words: [TranscriptWord(word: "steady_jump", start: 0.08, end: 0.60)]
    ),
    result: jumpResult
  )[0]
  try check(
    (jumpWord.pitch.rangeSemitones ?? 99) < 2.0,
    "P10-P90 pitch range did not reject the octave jump spike")

  // Robustness test: Word loudness uses active-speech frames, ignoring surrounding silence
  let silenceWithWordTimes = (0..<12).map { 0.10 + Double($0) * 0.05 }
  // 8 frames of silence at -60 dBFS, 4 frames of active speech at -20 dBFS
  let loudnessValues = [Double](repeating: -60.0, count: 8) + [Double](repeating: -20.0, count: 4)
  let wordInSilenceResult = AnalysisResult(
    metrics: steadyResult.metrics,
    loudnessContour: steadyResult.loudnessContour,
    pitchContour: steadyResult.pitchContour,
    waveform: steadyResult.waveform,
    spectrogram: steadyResult.spectrogram,
    acousticFrames: AcousticFrameData(
      loudness: zip(silenceWithWordTimes, loudnessValues).map { TimePoint(time: $0, value: $1) },
      pitch: []
    )
  )
  let wordInSilence = WordAcousticAnalyzer().analyze(
    transcription: TranscriptionResult(
      text: "delayed",
      words: [TranscriptWord(word: "delayed", start: 0.08, end: 0.70)]
    ),
    result: wordInSilenceResult
  )[0]
  try check(
    abs(wordInSilence.loudness.activeFrameCoverage - (4.0 / 12.0)) < 0.02,
    "Active frame coverage was inaccurate")
  let expectedMeanDB = -20.0 - steadyResult.metrics.meanLoudnessDBFS
  try check(
    abs((wordInSilence.loudness.relativeMeanDB ?? 0) - expectedMeanDB) < 0.1,
    "Word loudness was dragged down by silence frames instead of using active-only frames")

  // Pitch accuracy at 220 Hz
  let tone220 = (0..<Int(sampleRate * 0.5)).map { index in
    Float(0.35 * sin(2 * .pi * 220.0 * Double(index) / sampleRate))
  }
  let tone220Result = AudioAnalyzer().analyze(samples: tone220, sampleRate: sampleRate)
  try check(tone220Result.metrics.medianPitchHz != nil, "220 Hz pitch was not detected")
  try check(
    abs((tone220Result.metrics.medianPitchHz ?? 0) - 220.0) < 3.0,
    "220 Hz pitch estimate was inaccurate")

  // Continuity-aware octave-error correction and contour preservation test:
  // Verify that a pitch trajectory containing an artificial octave jump is corrected
  // without flattening the surrounding contour (e.g. 160, 165, 170, 338, 172, 168 Hz -> ~169 Hz).
  let octaveInput = [160.0, 165.0, 170.0, 338.0, 172.0, 168.0]
  let octaveTimes = (0..<6).map { Double($0) * 0.010 }
  let rawOctavePoints: [AudioAnalyzer.PitchPoint?] = zip(octaveTimes, octaveInput).map {
    AudioAnalyzer.PitchPoint(time: $0, frequency: $1, hnr: 15.0)
  }
  let correctedTrack = AudioAnalyzer().correctOctaveErrorsAndOutliers(track: rawOctavePoints)
  let correctedFrequencies = correctedTrack.compactMap { $0?.frequency }
  try check(correctedFrequencies.count == 6, "Octave correction dropped valid frames")
  try check(abs(correctedFrequencies[0] - 160.0) < 0.1, "Contour frame 0 was flattened/altered")
  try check(abs(correctedFrequencies[1] - 165.0) < 0.1, "Contour frame 1 was flattened/altered")
  try check(abs(correctedFrequencies[2] - 170.0) < 0.1, "Contour frame 2 was flattened/altered")
  try check(
    abs(correctedFrequencies[3] - 169.0) < 0.5,
    "Octave jump at 338 Hz was not corrected to ~169 Hz (got \(correctedFrequencies[3]))")
  try check(abs(correctedFrequencies[4] - 172.0) < 0.1, "Contour frame 4 was flattened/altered")
  try check(abs(correctedFrequencies[5] - 168.0) < 0.1, "Contour frame 5 was flattened/altered")

  // Multi-frame octave halving run test: verify a 3-frame octave dip is corrected
  let halvingInput = [160.0, 162.0, 75.8, 75.5, 75.6, 164.0, 166.0]
  let halvingTimes = (0..<7).map { Double($0) * 0.010 }
  let rawHalvingPoints: [AudioAnalyzer.PitchPoint?] = zip(halvingTimes, halvingInput).map {
    AudioAnalyzer.PitchPoint(time: $0, frequency: $1, hnr: 15.0)
  }
  let correctedHalvingTrack = AudioAnalyzer().correctOctaveErrorsAndOutliers(
    track: rawHalvingPoints)
  let correctedHalvingFreqs = correctedHalvingTrack.compactMap { $0?.frequency }
  try check(correctedHalvingFreqs.count == 7, "Multi-frame halving correction dropped frames")
  try check(
    abs(correctedHalvingFreqs[2] - 151.6) < 0.5, "Halving frame 2 was not doubled to ~151.6 Hz")
  try check(
    abs(correctedHalvingFreqs[3] - 151.0) < 0.5, "Halving frame 3 was not doubled to ~151.0 Hz")
  try check(
    abs(correctedHalvingFreqs[4] - 151.2) < 0.5, "Halving frame 4 was not doubled to ~151.2 Hz")

  // Outlier rejection test: verify an isolated non-harmonic outlier is rejected
  let outlierInput = [160.0, 165.0, 170.0, 260.0, 172.0, 168.0]
  let rawOutlierPoints: [AudioAnalyzer.PitchPoint?] = zip(octaveTimes, outlierInput).map {
    AudioAnalyzer.PitchPoint(time: $0, frequency: $1, hnr: 15.0)
  }
  let correctedOutlierTrack = AudioAnalyzer().correctOctaveErrorsAndOutliers(
    track: rawOutlierPoints)
  try check(correctedOutlierTrack[3] == nil, "Isolated non-harmonic outlier was not rejected")
  try check(correctedOutlierTrack[0]?.frequency == 160.0, "Surrounding context frame 0 was altered")
  try check(correctedOutlierTrack[5]?.frequency == 168.0, "Surrounding context frame 5 was altered")

  // Expressive intonation glide preservation test: verify a genuine pitch rise is completely preserved
  let glideInput = [150.0, 155.0, 162.0, 170.0, 180.0, 192.0]
  let rawGlidePoints: [AudioAnalyzer.PitchPoint?] = zip(octaveTimes, glideInput).map {
    AudioAnalyzer.PitchPoint(time: $0, frequency: $1, hnr: 15.0)
  }
  let correctedGlideTrack = AudioAnalyzer().correctOctaveErrorsAndOutliers(track: rawGlidePoints)
  let correctedGlideFrequencies = correctedGlideTrack.compactMap { $0?.frequency }
  try check(
    correctedGlideFrequencies == glideInput, "Genuine intonation glide was altered or smoothed")

  #if canImport(AVFoundation)
    if let timelineIndex = CommandLine.arguments.firstIndex(of: "--timeline"),
      CommandLine.arguments.indices.contains(timelineIndex + 1)
    {
      let audioURL = URL(fileURLWithPath: CommandLine.arguments[timelineIndex + 1])
      let liveResult = try AudioAnalyzer().analyze(url: audioURL)
      let liveTranscription = try NemoSpeechTranscriber().transcribe(url: audioURL)
      let liveWords = WordAcousticAnalyzer().analyze(
        transcription: liveTranscription,
        result: liveResult
      )
      let liveSession = PracticeSession(
        audioURL: audioURL,
        result: liveResult,
        transcription: liveTranscription,
        words: liveWords
      )
      print(ReportFormatter.makeTimelineDebug(session: liveSession))
    }

    if let pitchIndex = CommandLine.arguments.firstIndex(of: "--inspect-pitch"),
      CommandLine.arguments.indices.contains(pitchIndex + 1)
    {
      let audioURL = URL(fileURLWithPath: CommandLine.arguments[pitchIndex + 1])
      let liveResult = try AudioAnalyzer().analyze(url: audioURL)
      print("Median Hz: \(liveResult.metrics.medianPitchHz ?? 0)")
      print("Pitch Range Semitones: \(liveResult.metrics.pitchRangeSemitones ?? 0)")
      print("Pitch points count: \(liveResult.acousticFrames.pitch.count)")
      let pts = liveResult.acousticFrames.pitch
      for i in 1..<pts.count {
        let jump = 12 * log2(pts[i].value / pts[i - 1].value)
        let dt = pts[i].time - pts[i - 1].time
        if abs(jump) >= 5.0 && dt < 0.05 {
          print(
            String(
              format: "Jump at %.3fs -> %.3fs (dt=%.3f): %.1f Hz -> %.1f Hz (%.2f st)",
              pts[i - 1].time, pts[i].time, dt, pts[i - 1].value, pts[i].value, jump))
        }
      }
      if let sIdx = CommandLine.arguments.firstIndex(of: "--start"),
        let eIdx = CommandLine.arguments.firstIndex(of: "--end"),
        let sVal = Double(CommandLine.arguments[sIdx + 1]),
        let eVal = Double(CommandLine.arguments[eIdx + 1])
      {
        print("Frames in range [\(sVal), \(eVal)]:")
        for p in pts where p.time >= sVal && p.time <= eVal {
          print(String(format: "  t=%.3f: %.1f Hz", p.time, p.value))
        }
      }
    }

    if let argumentIndex = CommandLine.arguments.firstIndex(of: "--transcribe"),
      CommandLine.arguments.indices.contains(argumentIndex + 1)
    {
      let audioURL = URL(fileURLWithPath: CommandLine.arguments[argumentIndex + 1])
      let liveResult = try AudioAnalyzer().analyze(url: audioURL)
      let liveTranscription = try NemoSpeechTranscriber().transcribe(url: audioURL)
      let liveWords = WordAcousticAnalyzer().analyze(
        transcription: liveTranscription,
        result: liveResult
      )
      try check(
        !liveTranscription.text.isEmpty, "Live Parakeet smoke test returned an empty transcript")
      try check(!liveWords.isEmpty, "Live Parakeet smoke test returned no timestamped words")
      let liveSession = PracticeSession(
        audioURL: audioURL,
        result: liveResult,
        transcription: liveTranscription,
        words: liveWords
      )
      if CommandLine.arguments.contains("--timeline") {
        print(ReportFormatter.makeTimelineDebug(session: liveSession))
      }
      print(ReportFormatter.makeReport(session: liveSession))
    }

    if let argumentIndex = CommandLine.arguments.firstIndex(of: "--transcribe-system"),
      CommandLine.arguments.indices.contains(argumentIndex + 1)
    {
      let audioURL = URL(fileURLWithPath: CommandLine.arguments[argumentIndex + 1])
      let liveResult = try AudioAnalyzer().analyze(url: audioURL)
      let outcome = try await TranscriptionService(preferredEngine: .system).transcribe(
        url: audioURL)
      let liveWords = WordAcousticAnalyzer().analyze(
        transcription: outcome.result,
        result: liveResult
      )
      try check(
        !outcome.result.text.isEmpty, "Live Apple speech smoke test returned an empty transcript")
      try check(!liveWords.isEmpty, "Live Apple speech smoke test returned no timestamped words")
      print("Apple engine used: \(outcome.engine.rawValue)")
      if let notice = outcome.notice {
        print("Notice: \(notice)")
      }
      let liveSession = PracticeSession(
        audioURL: audioURL,
        result: liveResult,
        transcription: outcome.result,
        words: liveWords
      )
      if CommandLine.arguments.contains("--timeline") {
        print(ReportFormatter.makeTimelineDebug(session: liveSession))
      }
      print(ReportFormatter.makeReport(session: liveSession))
    }
  #endif

  if CommandLine.arguments.contains("--dump-sample-report") {
    print(report)
  }

  print("VoiceCoach analysis self-test passed")
} catch {
  FileHandle.standardError.write(
    Data("VoiceCoach analysis self-test failed: \(error.localizedDescription)\n".utf8))
  exit(1)
}
