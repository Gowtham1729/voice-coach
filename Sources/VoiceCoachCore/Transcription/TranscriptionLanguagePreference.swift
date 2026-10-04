import Foundation

/// Empty means use the Mac's locale as a default; explicit choices never change system settings.
public enum TranscriptionLanguagePreference {
  public static let storageKey = "voiceCoach.transcriptionLocale"

  public static func load(defaults: UserDefaults = .standard) -> String {
    defaults.string(forKey: storageKey) ?? ""
  }

  public static func locale(for identifier: String) -> Locale {
    identifier.isEmpty ? .current : Locale(identifier: identifier)
  }

  public static func requestedLocale(
    for identifier: String, engine: TranscriptionEnginePreference
  ) -> Locale? {
    engine == .system ? locale(for: identifier) : nil
  }

  public static func displayName(for identifier: String) -> String {
    let baseIdentifier = String(identifier.split(separator: "@").first ?? Substring(identifier))
    return Locale.current.localizedString(forIdentifier: baseIdentifier) ?? identifier
  }

  /// Never substitute an unrelated language when the requested locale is unsupported.
  public static func matchingLocale(for preferred: Locale, supported: [Locale]) -> Locale? {
    let language = preferred.language.languageCode
    guard let language else { return nil }
    let candidates = supported.filter { $0.language.languageCode == language }
      .sorted { $0.identifier < $1.identifier }
    return candidates.first(where: { $0.region == preferred.region }) ?? candidates.first
  }
}
