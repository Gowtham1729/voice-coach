import Combine
import Foundation
import VoiceCoachCore
import VoiceCoachSession

@MainActor
final class AppModel: ObservableObject {
  @Published var destination: AppDestination = .home
  @Published var sessions: [CoachingSession] = []
  @Published var selectedSessionID: UUID?
  @Published var selectedTakeID: UUID?
  @Published var pendingReplaceOnly: ReplaceOnlyPrompt?
  @Published var lastUsedMimicID: UUID?
  @Published var isRecording = false
  @Published var isCapturingMimicReference = false
  @Published var isAnalyzing = false
  @Published var isSuggestingTitle = false
  @Published var isRequestingPermission = false
  @Published var isPlaying = false
  @Published var playbackTime: TimeInterval = 0
  @Published var elapsed: TimeInterval = 0
  @Published var liveLevel: Double = -80
  @Published var mimicReferenceCaptureElapsed: TimeInterval = 0
  @Published var mimicReferenceCaptureLevel: Double = -80
  @Published var errorTitle = "Voice Coach"
  @Published var errorMessage: String?
  @Published var toastMessage: String?
  @Published var transcriptionNotice: String?
  @Published var transcriptionSetupStatus: TranscriptionSetupStatus = .missing
  @Published var systemTranscriptionStatus: SystemTranscriptionStatus = .unavailable(
    "Checking speech…")
  @Published var transcriptionEngine: TranscriptionEnginePreference = .load()
  @Published var mimicDraft: MimicReferenceDraft?
  @Published var mimicIsPreparing = false
  @Published var mimicPhase: MimicPhase = .ready
  @Published var mimicWorkspaceMode: MimicWorkspaceMode = .practice
  @Published var mimicPlaybackSource: MimicPlaybackSource = .reference
  @Published var mimicSelectedWord: Int?
  @Published var mimicReferenceVolume: Double = 0.75 {
    didSet {
      if mimicPlaybackSource == .reference {
        recorder.playbackVolume = Float(mimicReferenceVolume)
      }
    }
  }
  @Published var pendingMimicTake: PracticeSession?
  @Published var pendingMimicAudio: (url: URL, id: UUID)?
  @Published var pendingMimicSessionID: UUID?

  let recorder: any AudioRecording
  let systemAudioCapture: any SystemAudioCapturing
  let store: any SessionStoring
  var timer: Timer?
  var playbackTimer: Timer?
  var mimicReferenceCaptureTimer: Timer?
  var recordingURL: URL?
  var recordingTakeID: UUID?
  var startedAt: Date?
  var mimicReferenceCaptureURL: URL?
  var mimicReferenceCaptureStartedAt: Date?
  var transcriptionSetupTask: Task<Void, Never>?
  var systemTranscriptionStatusTask: Task<Void, Never>?
  var systemAssetInstallTask: Task<Void, Never>?
  var mimicPreparationID: UUID?
  var mimicCountInTask: Task<Void, Never>?
  var mimicPlaybackEnd: Double?
  var mimicShouldRecordAfterPlayback = false
  var mimicAlong = false
  var pendingCaptureIsNewSession = false
  var pendingImportSourceURL: URL?

  init(
    storageRoot: URL? = nil,
    loadPersistedData: Bool = true,
    dependencies: AppDependencies? = nil
  ) {
    do {
      let dependencies = try dependencies ?? AppDependencies.live(storageRoot: storageRoot)
      recorder = dependencies.recorder
      systemAudioCapture = dependencies.systemAudioCapture
      store = dependencies.sessionStore
    } catch {
      fatalError("Voice Coach could not open local storage: \(error.localizedDescription)")
    }

    recorder.onPlaybackFinished = { [weak self] in
      guard let self else { return }
      self.finishMimicPlayback()
    }
    recorder.onRecordingInterrupted = { [weak self] in
      guard let self, self.isRecording else { return }
      self.toastMessage = "Recording interrupted. Saving…"
      self.stopRecording()
    }
    systemAudioCapture.onCaptureInterrupted = { [weak self] in
      Task { @MainActor in
        guard let self, self.isCapturingMimicReference else { return }
        self.toastMessage = "Capture interrupted. Using what was recorded."
        self.finishMimicReferenceCapture()
      }
    }

    refreshTranscriptionSetupStatus()
    refreshSystemTranscriptionStatus()

    guard loadPersistedData else { return }
    do {
      sessions = try store.load()
      lastUsedMimicID = sessions.first(where: { $0.isMimic && !$0.archived })?.id
    } catch {
      presentError(
        title: "Library couldn’t be loaded",
        message: "Existing files were left untouched. Try quitting and reopening Voice Coach.")
    }
  }

  func presentError(title: String, message: String) {
    errorTitle = title
    errorMessage = message
  }

  func presentError(title: String, error: Error, fallback: String) {
    presentError(title: title, message: Self.userFacingMessage(error, fallback: fallback))
  }

  func clearError() {
    errorTitle = "Voice Coach"
    errorMessage = nil
  }

  static func userFacingMessage(_ error: Error, fallback: String) -> String {
    guard let description = appAuthoredDescription(error) else { return fallback }
    return description
  }

  private static func appAuthoredDescription(_ error: Error) -> String? {
    let authored: String?
    switch error {
    case let error as RecorderError: authored = error.errorDescription
    case let error as AudioImportError: authored = error.errorDescription
    case let error as AnalysisError: authored = error.errorDescription
    case let error as TranscriptionError: authored = error.errorDescription
    case let error as TranscriptionSetupError: authored = error.errorDescription
    case let error as SystemAudioCaptureError: authored = error.errorDescription
    default: return nil
    }
    guard let authored, isShortUserFacing(authored) else { return nil }
    return authored
  }

  private static func isShortUserFacing(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 220 else { return false }
    let lower = trimmed.lowercased()
    if lower.contains("error domain") || lower.contains("code=") || lower.contains("nserror")
      || lower.contains("osstatus") || lower.contains("posixerror")
    {
      return false
    }
    return true
  }

  var selectedSession: CoachingSession? {
    guard let selectedSessionID else { return nil }
    return sessions.first { $0.id == selectedSessionID }
  }

  var selectedTake: PracticeSession? {
    guard let selectedSession else { return nil }
    if let selectedTakeID,
      let take = selectedSession.takes.first(where: { $0.id == selectedTakeID })
    {
      return take
    }
    return selectedSession.latestTake
  }

  var reportCache: (takeID: UUID, value: String)?

  var report: String {
    guard let take = selectedTake else { return "" }
    if let reportCache, reportCache.takeID == take.id { return reportCache.value }
    let value = ReportFormatter.makeReport(session: take)
    reportCache = (take.id, value)
    return value
  }
  var storageLocation: URL { store.rootURL }
  var isMimicWorkspace: Bool {
    guard selectedSession?.mode == .mimic else { return false }
    switch destination {
    case .practice: return true
    case .home, .mimicStart, .take, .library, .mimics: return false
    }
  }
  var hasPendingMimicWork: Bool {
    pendingMimicSessionID == selectedSessionID
      && (pendingMimicTake != nil || pendingMimicAudio != nil)
  }
  var showsTakeInspector: Bool {
    if destination.isTake { return true }
    return selectedSession?.mode == .mimic && mimicWorkspaceMode == .analysis
  }
  var libraryRecordings: [LibraryRecording] {
    RecordingCatalog.recordings(from: sessions)
  }
  var mimicSessions: [CoachingSession] {
    sessions.filter { $0.isMimic && !$0.archived }
  }
  var archivedMimicSessions: [CoachingSession] {
    sessions.filter { $0.isMimic && $0.archived }
  }
  var emptyLegacySessions: [CoachingSession] {
    sessions.filter(\.isEmptyLegacy)
  }
  var continueMimic: CoachingSession? {
    if let lastUsedMimicID,
      let session = sessions.first(where: { $0.id == lastUsedMimicID && $0.isMimic && !$0.archived }
      )
    {
      return session
    }
    return mimicSessions.first
  }
  var userRecordedTakeCount: Int {
    sessions.reduce(0) { $0 + $1.takes.filter { $0.takeSource == .recorded }.count }
  }
  var userRecordedDuration: Double {
    sessions.reduce(0) { $0 + $1.userRecordedDuration() }
  }
  var importedTakeCount: Int {
    sessions.reduce(0) { $0 + $1.takes.filter { $0.takeSource != .recorded }.count }
  }
  var totalTakeCount: Int { sessions.reduce(0) { $0 + $1.takeCount } }
}
