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
        return await resolveLocale(for: .current) != nil
        #else
        false
        #endif
    }

    public static func currentStatus(preferredLocale: Locale = .current) async -> SystemTranscriptionStatus {
        #if canImport(Speech)
        guard SpeechTranscriber.isAvailable else {
            return .unavailable("Apple SpeechTranscriber is not available on this Mac.")
        }
        guard let locale = await resolveLocale(for: preferredLocale) else {
            return .unavailable("No Apple speech locale matches \(preferredLocale.identifier).")
        }

        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier == locale.identifier }) {
            return .ready(localeIdentifier: locale.identifier)
        }

        switch await AssetInventory.status(forModules: [SpeechTranscriber(locale: locale, preset: .transcription)]) {
        case .installed:
            return .ready(localeIdentifier: locale.identifier)
        case .downloading:
            return .downloading(localeIdentifier: locale.identifier)
        case .supported:
            return .needsDownload(localeIdentifier: locale.identifier)
        case .unsupported:
            return .unavailable("Apple speech assets are unsupported for \(locale.identifier).")
        @unknown default:
            return .unavailable("Apple speech asset status is unknown for \(locale.identifier).")
        }
        #else
        return .unavailable("Apple speech transcription requires the Speech framework.")
        #endif
    }

    public static func ensureAssets(preferredLocale: Locale = .current) async throws {
        #if canImport(Speech)
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionError.systemUnavailable("Apple SpeechTranscriber is not available on this Mac.")
        }
        guard let locale = await resolveLocale(for: preferredLocale) else {
            throw TranscriptionError.systemLocaleUnsupported(preferredLocale.identifier)
        }
        try await installAssetsIfNeeded(for: locale)
        #else
        throw TranscriptionError.systemUnavailable("Apple speech transcription requires the Speech framework.")
        #endif
    }

    public func transcribe(url: URL) async throws -> TranscriptionResult {
        #if canImport(Speech) && canImport(AVFoundation)
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionError.systemUnavailable("Apple SpeechTranscriber is not available on this Mac.")
        }
        guard let resolvedLocale = await Self.resolveLocale(for: locale) else {
            throw TranscriptionError.systemLocaleUnsupported(locale.identifier)
        }

        try await Self.installAssetsIfNeeded(for: resolvedLocale)

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

        let collector = TranscriptCollector()
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
        guard !payload.text.isEmpty || !payload.words.isEmpty else {
            throw TranscriptionError.invalidOutput
        }
        return payload
        #else
        throw TranscriptionError.systemUnavailable("Apple speech transcription requires Speech and AVFoundation.")
        #endif
    }

    #if canImport(Speech)
    static func resolveLocale(for preferred: Locale) async -> Locale? {
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: preferred) {
            return match
        }
        let preferredLanguage = preferred.language.languageCode?.identifier
        let supported = await SpeechTranscriber.supportedLocales
        if let preferredLanguage,
           let match = supported.first(where: { $0.language.languageCode?.identifier == preferredLanguage }) {
            return match
        }
        return supported.first
    }

    private static func installAssetsIfNeeded(for locale: Locale) async throws {
        do {
            _ = try await AssetInventory.reserve(locale: locale)
        } catch {
            // Reservation can fail when the slot is already held; installation may still succeed.
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
        case .installed, .supported:
            // `.supported` remains usable when the locale is already shared on the system.
            return
        case .downloading:
            throw TranscriptionError.systemAssetsUnavailable(
                "Apple speech model for \(locale.identifier) is still downloading."
            )
        case .unsupported:
            throw TranscriptionError.systemLocaleUnsupported(locale.identifier)
        @unknown default:
            throw TranscriptionError.systemAssetsUnavailable(
                "Apple speech model for \(locale.identifier) is not ready."
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
            "Apple SpeechTranscriber · \(locale) · on-device"
        case .needsDownload(let locale):
            "Download the shared Apple speech model for \(locale). Acoustic analysis still works without it."
        case .downloading(let locale):
            "Downloading Apple speech model for \(locale)…"
        case .unavailable(let message):
            message
        }
    }
}

#if canImport(Speech)
private actor TranscriptCollector {
    private var words: [TranscriptWord] = []
    private var textParts: [String] = []
    private(set) var failure: Error?

    func fail(_ error: Error) {
        if failure == nil { failure = error }
    }

    func consume(_ result: SpeechTranscriber.Result) {
        guard result.isFinal else { return }

        let attributed = result.text
        let plain = String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        if !plain.isEmpty { textParts.append(plain) }

        for run in attributed.runs {
            let token = String(attributed[run.range].characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }

            let attributes = run.attributes
            let timing = Self.seconds(in: attributes.audioTimeRange ?? result.range)
            appendWords(
                from: token,
                start: timing.start,
                end: timing.end,
                confidence: attributes.transcriptionConfidence
            )
        }
    }

    func makeResult() -> TranscriptionResult {
        let sorted = words.sorted {
            $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
        }
        let joined = textParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = sorted.map(\.word).joined(separator: " ")
        return TranscriptionResult(text: joined.isEmpty ? fallback : joined, words: sorted)
    }

    private func appendWords(from token: String, start: Double, end: Double, confidence: Double?) {
        let parts = token.split { $0.isWhitespace }.map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }

        if parts.count == 1 {
            words.append(TranscriptWord(word: parts[0], start: start, end: end, confidence: confidence))
            return
        }

        let step = max(end - start, 0.001) / Double(parts.count)
        for (index, part) in parts.enumerated() {
            let partStart = start + Double(index) * step
            words.append(
                TranscriptWord(word: part, start: partStart, end: partStart + step, confidence: confidence)
            )
        }
    }

    private static func seconds(in range: CMTimeRange) -> (start: Double, end: Double) {
        let start = max(0, range.start.seconds)
        return (start, max(start, (range.start + range.duration).seconds))
    }
}
#endif
