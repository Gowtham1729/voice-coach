import Foundation
import VoiceCoachCore

/// One engine found under `SoundComparison/<id>/`.
struct SoundEngineInstall: Equatable, Sendable {
  let id: String
  let sizeBytes: Int
  /// False when the files are from another engine version: the engine needs reinstalling.
  let isCurrent: Bool
}

/// On-device Sound comparison engines (optional downloads, PS-2).
protocol SoundComparing: Sendable {
  func installedEngines() async -> [SoundEngineInstall]
  func analyzeReference(engineID: String, audioURL: URL, words: [SoundWord]) async throws
    -> ReferenceAnalysis
  /// `takeWords`: one per Reference word (`SoundComparisonWordMap.takeWords`).
  func compare(
    engineID: String, reference: ReferenceAnalysis, takeAudioURL: URL, takeWords: [SoundWord?]
  ) async throws -> SoundComparisonResult
  /// Removes the engine's files. Results in the library are removed by `AppModel`.
  func deleteEngine(_ engineID: String) async throws
}

/// No engines: the default for tests and previews.
struct NoSoundComparison: SoundComparing {
  func installedEngines() async -> [SoundEngineInstall] { [] }
  func analyzeReference(engineID: String, audioURL: URL, words: [SoundWord]) async throws
    -> ReferenceAnalysis
  { throw SoundComparisonError.engineNotInstalled(engineID) }
  func compare(
    engineID: String, reference: ReferenceAnalysis, takeAudioURL: URL, takeWords: [SoundWord?]
  ) async throws -> SoundComparisonResult
  { throw SoundComparisonError.engineNotInstalled(engineID) }
  func deleteEngine(_ engineID: String) async throws {}
}

/// Engines installed by `scripts/setup-sound-comparison.sh` in
/// `~/Library/Application Support/VoiceCoach/SoundComparison/<engine>/`. Models load on first
/// use and stay loaded; packages are compiled once into the engine's `compiled/` folder.
actor LocalSoundComparisonService: SoundComparing {
  let root: URL
  private var engines: [String: PhoneModelSoundComparisonEngine] = [:]

  init(root: URL = LocalSoundComparisonService.defaultRoot) {
    self.root = root
  }

  static var defaultRoot: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("VoiceCoach/SoundComparison", isDirectory: true)
  }

  func installedEngines() -> [SoundEngineInstall] {
    #if arch(arm64)
    let decoder = JSONDecoder()
    return ["lite", "full"].compactMap { id in
      let url = root.appendingPathComponent(id).appendingPathComponent("manifest.json")
      guard let data = try? Data(contentsOf: url),
        let manifest = try? decoder.decode(SoundEngineManifest.self, from: data),
        manifest.engineID == id
      else { return nil }
      return SoundEngineInstall(id: id, sizeBytes: manifest.sizeBytes, isCurrent: manifest.isCurrent)
    }
    #else
    return []  // D4: Apple silicon only
    #endif
  }

  func analyzeReference(engineID: String, audioURL: URL, words: [SoundWord]) async throws
    -> ReferenceAnalysis
  {
    let engine = try await engine(engineID)
    return try engine.analyzeReference(samples: Self.samples(audioURL), words: words)
  }

  func compare(
    engineID: String, reference: ReferenceAnalysis, takeAudioURL: URL, takeWords: [SoundWord?]
  ) async throws -> SoundComparisonResult {
    let engine = try await engine(engineID)
    return try engine.compare(
      reference: reference, takeSamples: Self.samples(takeAudioURL),
      takeWords: takeWords)
  }

  /// Any read failure becomes `unreadableAudio`, so the app can tell it from an engine failure.
  private static func samples(_ url: URL) throws -> [Float] {
    do { return try SoundComparisonAudio.load(url) } catch {
      throw SoundComparisonError.unreadableAudio
    }
  }

  func deleteEngine(_ engineID: String) throws {
    engines[engineID] = nil
    let directory = root.appendingPathComponent(engineID, isDirectory: true)
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    try FileManager.default.removeItem(at: directory)
  }

  private func engine(_ id: String) async throws -> PhoneModelSoundComparisonEngine {
    if let engine = engines[id] { return engine }
    guard installedEngines().contains(where: { $0.id == id && $0.isCurrent }) else {
      throw SoundComparisonError.engineNotInstalled(id)
    }
    let engine = try await PhoneModelSoundComparisonEngine.load(
      installedAt: root.appendingPathComponent(id, isDirectory: true))
    engines[id] = engine
    return engine
  }
}

/// The active engine id (FR-25). Default: `full` when installed, else the only installed one.
enum SoundComparisonEnginePreference {
  static let storageKey = "voiceCoach.soundComparisonEngine"

  static func active(among installed: [SoundEngineInstall], defaults: UserDefaults = .standard)
    -> String?
  {
    let ready = installed.filter(\.isCurrent).map(\.id)
    if let stored = defaults.string(forKey: storageKey), ready.contains(stored) { return stored }
    return ready.contains("full") ? "full" : ready.first
  }

  static func save(_ id: String, defaults: UserDefaults = .standard) {
    defaults.set(id, forKey: storageKey)
  }
}
