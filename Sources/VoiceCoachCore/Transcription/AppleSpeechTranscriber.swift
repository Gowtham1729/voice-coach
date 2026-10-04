import Foundation

#if canImport(AVFoundation)
  @preconcurrency import AVFoundation
#endif

#if canImport(Speech)
  import CoreMedia
  import Speech
#endif

/// On-device Apple SpeechAnalyzer / SpeechTranscriber adapter (macOS 26+).
/// Audio stays on device; language models are system-managed via AssetInventory.
public struct AppleSpeechTranscriber: Sendable {
  public var locale: Locale

  public init(locale: Locale = .current) {
    self.locale = locale
  }

  public static func isAvailable() async -> Bool {
    #if canImport(Speech)
      guard SpeechTranscriber.isAvailable else { return false }
      return !(await SpeechTranscriber.supportedLocales).isEmpty
    #else
      false
    #endif
  }

  public static func supportedLocales() async -> [Locale] {
    #if canImport(Speech)
      return await SpeechTranscriber.supportedLocales
    #else
      return []
    #endif
  }

  public static func currentStatus(preferredLocale: Locale = .current) async
    -> SystemTranscriptionStatus
  {
    #if canImport(Speech)
      guard SpeechTranscriber.isAvailable else {
        return .unavailable("Speech transcription isn’t available on this Mac.")
      }
      guard let locale = await resolveLocale(for: preferredLocale) else {
        return .unavailable("No speech locale matches \(preferredLocale.identifier).")
      }

      let installed = await SpeechTranscriber.installedLocales
      if installed.contains(where: { $0.identifier == locale.identifier }) {
        return .ready(localeIdentifier: locale.identifier)
      }

      switch await AssetInventory.status(forModules: [
        SpeechTranscriber(locale: locale, preset: .transcription)
      ]) {
      case .installed:
        return .ready(localeIdentifier: locale.identifier)
      case .downloading:
        return .downloading(localeIdentifier: locale.identifier)
      case .supported:
        return .needsDownload(localeIdentifier: locale.identifier)
      case .unsupported:
        return .unavailable("Speech models aren’t supported for \(locale.identifier).")
      @unknown default:
        return .unavailable("Speech model status is unknown for \(locale.identifier).")
      }
    #else
      return .unavailable("Speech transcription requires the Speech framework.")
    #endif
  }

  public static func ensureAssets(preferredLocale: Locale = .current) async throws {
    #if canImport(Speech)
      guard SpeechTranscriber.isAvailable else {
        throw TranscriptionError.systemUnavailable(
          "Speech transcription isn’t available on this Mac.")
      }
      guard let locale = await resolveLocale(for: preferredLocale) else {
        throw TranscriptionError.systemLocaleUnsupported(preferredLocale.identifier)
      }
      try await installAssetsIfNeeded(for: locale)
    #else
      throw TranscriptionError.systemUnavailable(
        "Speech transcription requires the Speech framework.")
    #endif
  }

  public func transcribe(url: URL) async throws -> TranscriptionResult {
    #if canImport(Speech) && canImport(AVFoundation)
      guard SpeechTranscriber.isAvailable else {
        throw TranscriptionError.systemUnavailable(
          "Speech transcription isn’t available on this Mac.")
      }
      guard let resolvedLocale = await Self.resolveLocale(for: locale) else {
        throw TranscriptionError.systemLocaleUnsupported(locale.identifier)
      }

      guard await Self.currentStatus(preferredLocale: resolvedLocale).isReady else {
        throw TranscriptionError.systemAssetsUnavailable(
          "Download the Apple speech model for \(TranscriptionLanguagePreference.displayName(for: resolvedLocale.identifier)) in Settings → Transcription. Audio analysis and saving still work."
        )
      }

      let preset = SpeechTranscriber.Preset.timeIndexedTranscriptionWithAlternatives
      let transcriber = SpeechTranscriber(
        locale: resolvedLocale,
        transcriptionOptions: preset.transcriptionOptions,
        reportingOptions: [],
        attributeOptions: [.audioTimeRange, .transcriptionConfidence]
      )

      let file: AVAudioFile
      do {
        file = try AVAudioFile(forReading: url)
      } catch {
        throw TranscriptionError.launchFailed(error.localizedDescription)
      }
      guard file.length > 0 else {
        throw TranscriptionError.recognitionFailed("Audio file is empty.")
      }

      let collector = TranscriptCollector(locale: resolvedLocale)
      let analyzer = SpeechAnalyzer(modules: [transcriber])
      let collectTask = Task {
        do {
          for try await result in transcriber.results {
            await collector.consume(result)
          }
        } catch is CancellationError {
        } catch {
          await collector.fail(error)
        }
      }

      do {
        let lastSampleTime = try await analyzer.analyzeSequence(from: file)
        if let lastSampleTime {
          try await analyzer.finalizeAndFinish(through: lastSampleTime)
        } else {
          await analyzer.cancelAndFinishNow()
        }
      } catch {
        collectTask.cancel()
        throw TranscriptionError.recognitionFailed(error.localizedDescription)
      }

      await collectTask.value
      if let error = await collector.failure {
        throw TranscriptionError.recognitionFailed(error.localizedDescription)
      }

      let payload = await collector.makeResult()
      try RecordingValidation.validateTranscription(payload)
      return TranscriptionResult(
        text: payload.text, words: payload.words,
        localeIdentifier: resolvedLocale.identifier, engine: .system
      )
    #else
      throw TranscriptionError.systemUnavailable(
        "Speech transcription requires Speech and AVFoundation.")
    #endif
  }

  #if canImport(Speech)
    static func resolveLocale(for preferred: Locale) async -> Locale? {
      if let match = await SpeechTranscriber.supportedLocale(equivalentTo: preferred) {
        return match
      }
      return TranscriptionLanguagePreference.matchingLocale(
        for: preferred, supported: await SpeechTranscriber.supportedLocales
      )
    }

    private static func installAssetsIfNeeded(for locale: Locale) async throws {
      do {
        _ = try await AssetInventory.reserve(locale: locale)
      } catch {
        throw TranscriptionError.systemAssetsUnavailable(
          "Apple couldn’t reserve this speech language. Its system speech-language limit may have been reached."
        )
      }

      let probe = SpeechTranscriber(locale: locale, preset: .transcription)
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
        do {
          try await request.downloadAndInstall()
        } catch {
          throw TranscriptionError.systemAssetsUnavailable(error.localizedDescription)
        }
      }

      switch await AssetInventory.status(forModules: [probe]) {
      case .installed:
        return
      case .supported:
        throw TranscriptionError.systemAssetsUnavailable(
          "The Apple speech model for \(locale.identifier) still needs to be downloaded."
        )
      case .downloading:
        throw TranscriptionError.systemAssetsUnavailable(
          "Speech model for \(locale.identifier) is still downloading."
        )
      case .unsupported:
        throw TranscriptionError.systemLocaleUnsupported(locale.identifier)
      @unknown default:
        throw TranscriptionError.systemAssetsUnavailable(
          "Speech model for \(locale.identifier) isn’t ready."
        )
      }
    }
  #endif
}

public enum SystemTranscriptionStatus: Sendable, Equatable {
  case unavailable(String)
  case needsDownload(localeIdentifier: String)
  case downloading(localeIdentifier: String)
  case ready(localeIdentifier: String)

  public var isReady: Bool {
    if case .ready = self { return true }
    return false
  }

  public var isBusy: Bool {
    if case .downloading = self { return true }
    return false
  }

  public var title: String {
    switch self {
    case .ready: "Ready"
    case .needsDownload: "Model needed"
    case .downloading: "Downloading"
    case .unavailable: "Unavailable"
    }
  }

  public var detail: String {
    switch self {
    case .ready(let locale):
      "\(locale) · on-device"
    case .needsDownload(let locale):
      "Download the speech model for \(locale). Analysis still works without it."
    case .downloading(let locale):
      "Downloading \(locale)…"
    case .unavailable(let message):
      message
    }
  }
}

#if canImport(Speech)
  private actor TranscriptCollector {
    private let locale: Locale
    private var words: [TranscriptWord] = []

    init(locale: Locale) { self.locale = locale }
    private var textParts: [String] = []
    private(set) var failure: Error?

    func fail(_ error: Error) {
      if failure == nil { failure = error }
    }

    func consume(_ result: SpeechTranscriber.Result) {
      guard result.isFinal else { return }

      let attributed = result.text
      let plain = String(attributed.characters)
      if !plain.isEmpty { textParts.append(plain) }

      words.append(
        contentsOf: AppleSpeechTranscriber.timedWords(
          in: attributed, fallbackRange: result.range, locale: locale))
    }

    func makeResult() -> TranscriptionResult {
      let sorted = words.sorted {
        $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
      }
      let joined = textParts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
      let fallback = sorted.map(\.word).joined(separator: " ")
      return TranscriptionResult(text: joined.isEmpty ? fallback : joined, words: sorted)
    }

  }

  extension AppleSpeechTranscriber {
    /// Confidence attributes can split a timed span; keep those fragments together.
    static func timedWords(
      in text: AttributedString, fallbackRange: CMTimeRange, locale: Locale = .current
    ) -> [TranscriptWord] {
      var words: [TranscriptWord] = []
      var ranges: [Range<Int>] = []
      var offset = 0
      var pendingOffset = 0
      var pendingText = ""
      var pendingRange: CMTimeRange?
      var pendingConfidence: Double?

      func flush() {
        guard let range = pendingRange else { return }
        let token = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = max(0, range.start.seconds)
        let end = max(start, (range.start + range.duration).seconds)
        guard !token.isEmpty, start.isFinite, end.isFinite else { return }
        // Keep Apple's actual spans; equal subdivision would invent word boundaries.
        words.append(
          TranscriptWord(word: token, start: start, end: end, confidence: pendingConfidence))
        ranges.append(pendingOffset..<(pendingOffset + pendingText.count))
      }

      for run in text.runs {
        let fragment = String(text[run.range].characters)
        defer { offset += fragment.count }
        let range = run.attributes.audioTimeRange ?? fallbackRange
        if let pendingRange, CMTimeRangeEqual(pendingRange, range) {
          pendingText += fragment
          if let old = pendingConfidence, let next = run.attributes.transcriptionConfidence {
            pendingConfidence = min(old, next)
          } else {
            pendingConfidence = nil
          }
        } else {
          flush()
          pendingRange = range
          pendingOffset = offset
          pendingText = fragment
          pendingConfidence = run.attributes.transcriptionConfidence
        }
      }
      flush()
      return AppleTranscriptSegmenter.group(
        words: words, ranges: ranges, text: String(text.characters), locale: locale)
    }
  }
#endif
