import Foundation

public enum TranscriptionError: LocalizedError, Sendable {
  case runtimeUnavailable
  case systemUnavailable(String)
  case systemLocaleUnsupported(String)
  case modelLanguageUnsupported(String)
  case systemAssetsUnavailable(String)
  case launchFailed(String)
  case recognitionFailed(String)
  case invalidOutput
  case noSpeechRecognized

  public var errorDescription: String? {
    switch self {
    case .runtimeUnavailable:
      return
        "Parakeet isn’t installed. Open Settings → Transcription to download it (~714 MB), or use System."
    case .systemUnavailable(let detail):
      return detail
    case .systemLocaleUnsupported(let identifier):
      return
        "Apple speech transcription doesn’t support \(TranscriptionLanguagePreference.displayName(for: identifier)) on this Mac. Choose a supported speech language in Ichido Settings → Transcription."
    case .modelLanguageUnsupported(let identifier):
      return
        "This Parakeet model doesn’t support \(TranscriptionLanguagePreference.displayName(for: identifier)). Choose Apple in Settings → Transcription."
    case .systemAssetsUnavailable(let detail):
      return detail
    case .launchFailed:
      return "Couldn’t start transcription."
    case .recognitionFailed(let detail):
      if detail.lowercased().contains("input must be a .wav") {
        return "This clip isn’t stored as WAV. Import it again to transcribe."
      }
      return "Transcription failed."
    case .invalidOutput:
      return "Transcription returned an unreadable result."
    case .noSpeechRecognized:
      return "No speech recognized. Try recording again."
    }
  }
}

/// Local Parakeet adapter for NVIDIA's native NeMo-Speech.cpp command-line runtime.
/// Audio is passed as a local file path and never uploaded by Ichido.
public struct NemoSpeechTranscriber: Sendable {
  public static let defaultModel = "nvidia/parakeet-tdt-0.6b-v3"

  public static func supports(locale: Locale) -> Bool {
    guard let language = locale.language.languageCode?.identifier else { return false }
    return [
      "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
      "lv", "lt", "mt", "pl", "pt", "ro", "ru", "sk", "sl", "es", "sv", "uk",
    ].contains(language)
  }

  public let executableURL: URL?
  public let modelIdentifier: String

  public init(
    executableURL: URL? = nil,
    modelIdentifier: String = NemoSpeechTranscriber.defaultModel
  ) {
    self.executableURL = executableURL
    self.modelIdentifier = modelIdentifier
  }

  public func transcribe(url: URL) throws -> TranscriptionResult {
    guard let executable = executableURL ?? Self.findExecutable() else {
      throw TranscriptionError.runtimeUnavailable
    }

    let fileManager = FileManager.default
    let outputDirectory = fileManager.temporaryDirectory
      .appendingPathComponent("voice-coach-transcription-\(UUID().uuidString)", isDirectory: true)
    do {
      try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: false)
    } catch {
      throw TranscriptionError.launchFailed(error.localizedDescription)
    }
    defer { try? fileManager.removeItem(at: outputDirectory) }

    let stdoutURL = outputDirectory.appendingPathComponent("stdout.json")
    let stderrURL = outputDirectory.appendingPathComponent("stderr.txt")
    guard fileManager.createFile(atPath: stdoutURL.path, contents: nil),
      fileManager.createFile(atPath: stderrURL.path, contents: nil)
    else { throw TranscriptionError.launchFailed("Could not create temporary output files.") }

    do {
      let stdout = try FileHandle(forWritingTo: stdoutURL)
      let stderr = try FileHandle(forWritingTo: stderrURL)
      defer {
        try? stdout.close()
        try? stderr.close()
      }

      let process = Process()
      process.executableURL = executable
      process.arguments = [
        "--quiet",
        "transcribe",
        url.path,
        "--model", modelIdentifier,
        "--json",
      ]
      process.standardOutput = stdout
      process.standardError = stderr

      do {
        try process.run()
      } catch {
        throw TranscriptionError.launchFailed(error.localizedDescription)
      }
      process.waitUntilExit()
      try? stdout.synchronize()
      try? stderr.synchronize()

      let output = (try? Data(contentsOf: stdoutURL)) ?? Data()
      if process.terminationStatus != 0 {
        let diagnostics = ((try? String(contentsOf: stderrURL, encoding: .utf8)) ?? "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        throw TranscriptionError.recognitionFailed(
          diagnostics.isEmpty
            ? "nemo-speech exited with status \(process.terminationStatus)." : diagnostics
        )
      }
      return try Self.parseOutput(output)
    }
  }

  public static func findExecutable(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundle: Bundle = .main,
    fileManager: FileManager = .default
  ) -> URL? {
    var candidates: [String] = []
    if let override = environment["VOICE_COACH_NEMO_SPEECH_PATH"], !override.isEmpty {
      candidates.append(override)
    }
    if let managed = try? TranscriptionSetupService.managedExecutableURL(fileManager: fileManager) {
      candidates.append(managed.path)
    }
    if let resourceURL = bundle.resourceURL {
      candidates.append(resourceURL.appendingPathComponent("nemo-speech").path)
    }
    candidates += [
      NSString(string: "~/.local/bin/nemo-speech").expandingTildeInPath,
      NSString(string: "~/Library/Application Support/NeMoSpeech/bin/nemo-speech")
        .expandingTildeInPath,
      "/opt/homebrew/bin/nemo-speech",
      "/usr/local/bin/nemo-speech",
    ]
    if let path = environment["PATH"] {
      candidates += path.split(separator: ":").map {
        URL(fileURLWithPath: String($0)).appendingPathComponent("nemo-speech").path
      }
    }

    return
      candidates
      .map { URL(fileURLWithPath: $0) }
      .first { fileManager.isExecutableFile(atPath: $0.path) }
  }

  public static func parseOutput(_ data: Data) throws -> TranscriptionResult {
    guard let object = decodeJSONObject(from: data),
      let payload = transcriptionPayload(in: object),
      let rawWords = payload["words"] as? [Any]
    else { throw TranscriptionError.invalidOutput }

    var hasMalformedWords = false
    let words = rawWords.compactMap { raw -> TranscriptWord? in
      guard let item = raw as? [String: Any],
        let rawWord = (item["word"] as? String) ?? (item["text"] as? String),
        let start = number(item, keys: ["start", "start_s", "start_time"])
      else {
        hasMalformedWords = true
        return nil
      }

      let suppliedEnd = number(item, keys: ["end", "end_s", "end_time"])
      let suppliedDuration = number(item, keys: ["duration", "duration_s"])
      guard start.isFinite,
        let end = suppliedEnd ?? suppliedDuration.map({ start + $0 }),
        end.isFinite,
        end >= start
      else {
        hasMalformedWords = true
        return nil
      }

      let cleaned = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleaned.isEmpty else { return nil }
      return TranscriptWord(
        word: cleaned,
        start: max(0, start),
        end: max(0, end),
        confidence: number(item, keys: ["confidence", "probability"])
      )
    }
    .sorted { lhs, rhs in
      lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
    }

    let text = ((payload["text"] as? String) ?? words.map(\.word).joined(separator: " "))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let result = TranscriptionResult(text: text, words: words)
    if !result.hasRecognizedSpeech, hasMalformedWords {
      throw TranscriptionError.invalidOutput
    }
    try RecordingValidation.validateTranscription(result)
    return result
  }

  private static func decodeJSONObject(from data: Data) -> Any? {
    if let object = try? JSONSerialization.jsonObject(with: data) {
      return object
    }
    guard let string = String(data: data, encoding: .utf8),
      let first = string.firstIndex(of: "{"),
      let last = string.lastIndex(of: "}"),
      first <= last
    else { return nil }
    return try? JSONSerialization.jsonObject(with: Data(string[first...last].utf8))
  }

  private static func transcriptionPayload(in object: Any) -> [String: Any]? {
    if let dictionary = object as? [String: Any] {
      if dictionary["words"] is [Any], dictionary["text"] is String {
        return dictionary
      }
      for value in dictionary.values {
        if let match = transcriptionPayload(in: value) { return match }
      }
    } else if let array = object as? [Any] {
      for value in array {
        if let match = transcriptionPayload(in: value) { return match }
      }
    }
    return nil
  }

  private static func number(_ dictionary: [String: Any], keys: [String]) -> Double? {
    for key in keys {
      if let number = dictionary[key] as? NSNumber { return number.doubleValue }
      if let string = dictionary[key] as? String, let number = Double(string) { return number }
    }
    return nil
  }
}
