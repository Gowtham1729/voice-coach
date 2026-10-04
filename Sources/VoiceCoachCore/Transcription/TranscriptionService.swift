import Foundation

public enum TranscriptionEnginePreference: String, CaseIterable, Sendable, Codable {
  case system
  case parakeet

  public static let storageKey = "voiceCoach.transcriptionEngine"
  public static let `default`: TranscriptionEnginePreference = .system

  public var title: String {
    switch self {
    case .system: "System (Apple)"
    case .parakeet: "Parakeet"
    }
  }

  public var detail: String {
    switch self {
    case .system:
      "On-device SpeechAnalyzer. Shared system models."
    case .parakeet:
      "Optional local Parakeet model (~714 MB)."
    }
  }

  public static func load(defaults: UserDefaults = .standard) -> TranscriptionEnginePreference {
    guard let raw = defaults.string(forKey: storageKey),
      let value = TranscriptionEnginePreference(rawValue: raw)
    else { return .default }
    return value
  }

  public func save(defaults: UserDefaults = .standard) {
    defaults.set(rawValue, forKey: Self.storageKey)
  }
}

public struct TranscriptionOutcome: Sendable, Equatable {
  public let result: TranscriptionResult
  public let engine: TranscriptionEnginePreference
  public let notice: String?

  public init(
    result: TranscriptionResult,
    engine: TranscriptionEnginePreference,
    notice: String? = nil
  ) {
    self.result = result
    self.engine = engine
    self.notice = notice
  }
}

/// Uses the selected on-device engine. Failures never silently switch models or languages.
public struct TranscriptionService: Sendable {
  public var preferredEngine: TranscriptionEnginePreference
  /// Apple uses this locale. Parakeet only checks it when the audio's language is known.
  public var locale: Locale?

  public init(
    preferredEngine: TranscriptionEnginePreference = .load(),
    locale: Locale? = nil
  ) {
    self.preferredEngine = preferredEngine
    self.locale = locale
  }

  public func transcribe(url: URL) async throws -> TranscriptionOutcome {
    switch preferredEngine {
    case .system:
      let result = try await AppleSpeechTranscriber(locale: locale ?? .current).transcribe(url: url)
      return TranscriptionOutcome(result: result, engine: .system)
    case .parakeet:
      if let locale, !NemoSpeechTranscriber.supports(locale: locale) {
        throw TranscriptionError.modelLanguageUnsupported(locale.identifier)
      }
      let result = try NemoSpeechTranscriber().transcribe(url: url)
      return TranscriptionOutcome(
        result: TranscriptionResult(
          text: result.text, words: result.words, engine: .parakeet
        ), engine: .parakeet
      )
    }
  }
}
