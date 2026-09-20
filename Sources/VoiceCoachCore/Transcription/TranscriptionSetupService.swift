import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum TranscriptionSetupPhase: String, Sendable, Equatable {
  case preparing
  case installingRuntime
  case downloadingModel
  case verifying

  public var userFacingLabel: String {
    switch self {
    case .preparing: "Preparing…"
    case .installingRuntime: "Installing runtime…"
    case .downloadingModel: "Downloading Parakeet (~714 MB)…"
    case .verifying: "Verifying…"
    }
  }
}

public enum TranscriptionSetupStatus: Sendable, Equatable {
  case unsupported(String)
  case missing
  case ready(runtimePath: String, modelID: String)
  case installing(TranscriptionSetupPhase)
  case failed(String)

  public var isReady: Bool {
    if case .ready = self { return true }
    return false
  }

  public var isBusy: Bool {
    if case .installing = self { return true }
    return false
  }

  public var title: String {
    switch self {
    case .ready: "Ready"
    case .missing: "Not installed"
    case .installing: "Installing"
    case .failed: "Needs attention"
    case .unsupported: "Unavailable"
    }
  }

  public var detail: String {
    switch self {
    case .ready(_, let modelID):
      "\(modelID) · local"
    case .missing:
      "Optional. System transcription works without it."
    case .installing(let phase):
      phase.userFacingLabel
    case .failed(let message), .unsupported(let message):
      message
    }
  }
}

public enum TranscriptionSetupError: LocalizedError, Sendable {
  case unsupportedArchitecture
  case downloadFailed(String)
  case installFailed(String)
  case pullFailed(String)
  case verificationFailed(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedArchitecture:
      return TranscriptionSetupService.appleSiliconRequirement
    case .downloadFailed:
      return "Couldn’t download the installer."
    case .installFailed:
      return "Couldn’t install the transcription runtime."
    case .pullFailed:
      return "Couldn’t download the Parakeet model."
    case .verificationFailed:
      return "Install finished, but verification failed."
    }
  }
}

/// Downloads NVIDIA NeMo-Speech.cpp (binary) + Parakeet into local caches for Voice Coach.
/// Recordings are never uploaded; only the runtime/model artifacts are fetched.
public struct TranscriptionSetupService: Sendable {
  public static let defaultModelID = NemoSpeechTranscriber.defaultModel
  public static let installScriptRemoteURL = URL(
    string: "https://github.com/NVIDIA/NeMo-Speech.cpp/raw/main/scripts/install.sh"
  )!

  public let modelID: String

  public init(modelID: String = TranscriptionSetupService.defaultModelID) {
    self.modelID = modelID
  }

  public static let appleSiliconRequirement =
    "Parakeet requires Apple Silicon."

  public static var isAppleSilicon: Bool {
    #if arch(arm64)
      true
    #else
      false
    #endif
  }

  public static func voiceCoachRootURL(fileManager: FileManager = .default) throws -> URL {
    try userDirectory(.applicationSupportDirectory, fileManager: fileManager)
      .appendingPathComponent("VoiceCoach", isDirectory: true)
  }

  public static func managedRuntimePrefixURL(fileManager: FileManager = .default) throws -> URL {
    try voiceCoachRootURL(fileManager: fileManager)
      .appendingPathComponent("Transcription/NeMoSpeech", isDirectory: true)
  }

  public static func managedExecutableURL(fileManager: FileManager = .default) throws -> URL {
    try managedRuntimePrefixURL(fileManager: fileManager)
      .appendingPathComponent("bin/nemo-speech", isDirectory: false)
  }

  public static func modelRepositoryCacheURL(
    modelID: String = defaultModelID,
    fileManager: FileManager = .default
  ) throws -> URL {
    try userDirectory(.cachesDirectory, fileManager: fileManager)
      .appendingPathComponent("NeMoSpeech/models/\(modelID)", isDirectory: true)
  }

  public static func currentStatus(
    modelID: String = defaultModelID,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) -> TranscriptionSetupStatus {
    guard isAppleSilicon else { return .unsupported(appleSiliconRequirement) }
    guard
      let executable = NemoSpeechTranscriber.findExecutable(
        environment: environment,
        fileManager: fileManager
      )
    else {
      return .missing
    }
    guard hasLocalModel(modelID: modelID, fileManager: fileManager) else { return .missing }
    return .ready(runtimePath: executable.path, modelID: modelID)
  }

  public static func hasLocalModel(
    modelID: String = defaultModelID,
    fileManager: FileManager = .default
  ) -> Bool {
    guard let root = try? modelRepositoryCacheURL(modelID: modelID, fileManager: fileManager),
      let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
    else { return false }

    for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "gguf" {
      return true
    }
    return false
  }

  public func installOrUpdate(
    onPhase: @Sendable @escaping (TranscriptionSetupPhase) -> Void = { _ in }
  ) async throws {
    guard Self.isAppleSilicon else { throw TranscriptionSetupError.unsupportedArchitecture }

    onPhase(.preparing)
    let fileManager = FileManager.default
    let prefix = try Self.managedRuntimePrefixURL(fileManager: fileManager)
    try fileManager.createDirectory(
      at: prefix.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let workDirectory = fileManager.temporaryDirectory
      .appendingPathComponent(
        "voice-coach-transcription-setup-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: workDirectory) }

    onPhase(.installingRuntime)
    let scriptURL = workDirectory.appendingPathComponent("install.sh")
    try await downloadInstallScript(to: scriptURL)

    try await runProcess(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: [
        scriptURL.path,
        "--binary-only",
        "--no-modify-path",
        "--backend", "metal",
        "--prefix", prefix.path,
      ],
      mapError: TranscriptionSetupError.installFailed
    )

    let executable = prefix.appendingPathComponent("bin/nemo-speech", isDirectory: false)
    guard fileManager.isExecutableFile(atPath: executable.path) else {
      throw TranscriptionSetupError.installFailed("Installed runtime is missing bin/nemo-speech.")
    }

    onPhase(.downloadingModel)
    try await runProcess(
      executable: executable,
      arguments: ["pull", modelID],
      mapError: TranscriptionSetupError.pullFailed
    )

    onPhase(.verifying)
    try await runProcess(
      executable: executable,
      arguments: ["doctor"],
      mapError: TranscriptionSetupError.verificationFailed
    )

    guard Self.hasLocalModel(modelID: modelID, fileManager: fileManager) else {
      throw TranscriptionSetupError.verificationFailed(
        "The Parakeet model files were not found in the local cache after download."
      )
    }
  }

  private func downloadInstallScript(to scriptURL: URL) async throws {
    do {
      let (data, response) = try await URLSession.shared.data(from: Self.installScriptRemoteURL)
      if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        throw TranscriptionSetupError.downloadFailed("HTTP \(http.statusCode)")
      }
      try data.write(to: scriptURL, options: .atomic)
    } catch let error as TranscriptionSetupError {
      throw error
    } catch {
      throw TranscriptionSetupError.downloadFailed(error.localizedDescription)
    }
  }

  private func runProcess(
    executable: URL,
    arguments: [String],
    mapError: @Sendable @escaping (String) -> TranscriptionSetupError
  ) async throws {
    try await Task.detached(priority: .userInitiated) {
      let fileManager = FileManager.default
      let outputDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("voice-coach-setup-proc-\(UUID().uuidString)", isDirectory: true)
      try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
      defer { try? fileManager.removeItem(at: outputDirectory) }

      let stdoutURL = outputDirectory.appendingPathComponent("stdout.txt")
      let stderrURL = outputDirectory.appendingPathComponent("stderr.txt")
      fileManager.createFile(atPath: stdoutURL.path, contents: nil)
      fileManager.createFile(atPath: stderrURL.path, contents: nil)

      let stdout = try FileHandle(forWritingTo: stdoutURL)
      let stderr = try FileHandle(forWritingTo: stderrURL)
      defer {
        try? stdout.close()
        try? stderr.close()
      }

      let process = Process()
      process.executableURL = executable
      process.arguments = arguments
      process.standardOutput = stdout
      process.standardError = stderr

      do {
        try process.run()
      } catch {
        throw mapError(error.localizedDescription)
      }
      process.waitUntilExit()
      try? stdout.synchronize()
      try? stderr.synchronize()

      guard process.terminationStatus == 0 else {
        throw mapError(
          Self.processFailureDetail(
            stdoutURL: stdoutURL,
            stderrURL: stderrURL,
            status: process.terminationStatus
          ))
      }
    }.value
  }

  private static func processFailureDetail(stdoutURL: URL, stderrURL: URL, status: Int32) -> String
  {
    let stderrText = ((try? String(contentsOf: stderrURL, encoding: .utf8)) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !stderrText.isEmpty { return stderrText }

    let stdoutText = ((try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !stdoutText.isEmpty { return stdoutText }

    return "Process exited with status \(status)."
  }

  private static func userDirectory(
    _ directory: FileManager.SearchPathDirectory,
    fileManager: FileManager
  ) throws -> URL {
    try fileManager.url(
      for: directory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
  }
}
