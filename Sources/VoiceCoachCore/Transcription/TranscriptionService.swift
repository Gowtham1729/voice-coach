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

/// Chooses Apple SpeechAnalyzer by default, with optional Parakeet when selected or as fallback.
public struct TranscriptionService: Sendable {
  public var preferredEngine: TranscriptionEnginePreference
  public var locale: Locale

  public init(
    preferredEngine: TranscriptionEnginePreference = .load(),
    locale: Locale = .current
  ) {
    self.preferredEngine = preferredEngine
    self.locale = locale
  }

  public func transcribe(url: URL) async throws -> TranscriptionOutcome {
    switch preferredEngine {
    case .system:
      do {
        let result = try await AppleSpeechTranscriber(locale: locale).transcribe(url: url)
        return TranscriptionOutcome(result: result, engine: .system)
      } catch {
        guard TranscriptionSetupService.currentStatus().isReady else { throw error }
        let result = try NemoSpeechTranscriber().transcribe(url: url)
        return TranscriptionOutcome(
          result: result,
          engine: .parakeet,
          notice:
            "System transcription failed. Used Parakeet instead."
        )
      }
    case .parakeet:
      let result = try NemoSpeechTranscriber().transcribe(url: url)
      return TranscriptionOutcome(result: result, engine: .parakeet)
    }
  }
}
