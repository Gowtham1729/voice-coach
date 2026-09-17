import AppKit
import AVFoundation
import Foundation
import VoiceCoachCore

struct MimicReferenceDraft {
    let id: UUID
    let url: URL
    let sourceName: String
    let duration: Double
    let peaks: [Float]
    let source: TakeSource
}

enum MimicPhase: Equatable {
    case ready
    case playingReference
    case countIn(Int)
    case recording
    case analyzing
}

enum MimicPlaybackSource {
    case reference
    case attempt
}

@MainActor
final class AppModel: ObservableObject {
    @Published var destination: AppDestination = .studio
    @Published private(set) var sessions: [CoachingSession] = []
    @Published var selectedSessionID: UUID?
    @Published var selectedTakeID: UUID?
    @Published var isRecording = false
    @Published var isAnalyzing = false
    @Published var isRequestingPermission = false
    @Published var isPlaying = false
    @Published var playbackTime: TimeInterval = 0
    @Published var elapsed: TimeInterval = 0
    @Published var liveLevel: Double = -80
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    @Published var transcriptionNotice: String?
    @Published var transcriptionSetupStatus: TranscriptionSetupStatus = .missing
    @Published var systemTranscriptionStatus: SystemTranscriptionStatus = .unavailable("Checking system speech…")
    @Published var transcriptionEngine: TranscriptionEnginePreference = .load()
    @Published var mimicDraft: MimicReferenceDraft?
    @Published var mimicIsPreparing = false
    @Published var mimicPhase: MimicPhase = .ready
    @Published var mimicShowingResult = false
    @Published var mimicPlaybackSource: MimicPlaybackSource = .reference
    @Published var mimicHearingDifference = false
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

    private let recorder = AudioRecorder()
    private let store: SessionStore
    private var timer: Timer?
    private var playbackTimer: Timer?
    private var recordingURL: URL?
    private var recordingTakeID: UUID?
    private var startedAt: Date?
    private var transcriptionSetupTask: Task<Void, Never>?
    private var systemTranscriptionStatusTask: Task<Void, Never>?
    private var systemAssetInstallTask: Task<Void, Never>?
    private var mimicPreparationID: UUID?
    private var mimicCountInTask: Task<Void, Never>?
    private var mimicNextSegment: (url: URL, start: Double, end: Double)?
    private var mimicPlaybackEnd: Double?
    private var mimicShouldRecordAfterPlayback = false
    private var mimicAlong = false

    init(storageRoot: URL? = nil, loadPersistedData: Bool = true) {
        do {
            store = try SessionStore(rootURL: storageRoot)
        } catch {
            fatalError("Voice Coach could not open local storage: \(error.localizedDescription)")
        }

        recorder.onPlaybackFinished = { [weak self] in
            guard let self else { return }
            self.finishMimicPlayback()
        }
        recorder.onRecordingInterrupted = { [weak self] in
            guard let self, self.isRecording else { return }
            self.toastMessage = "Recording interrupted; saving the audio captured so far."
            self.stopRecording()
        }

        refreshTranscriptionSetupStatus()
        refreshSystemTranscriptionStatus()

        guard loadPersistedData else { return }
        do {
            sessions = try store.load()
            selectedSessionID = sessions.first?.id
            selectedTakeID = sessions.first?.latestTake?.id
        } catch {
            errorMessage = "Your saved sessions could not be loaded. The existing files were left untouched. \(error.localizedDescription)"
        }
    }

    var selectedSession: CoachingSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    var selectedTake: PracticeSession? {
        guard let selectedSession else { return nil }
        if let selectedTakeID, let take = selectedSession.takes.first(where: { $0.id == selectedTakeID }) {
            return take
        }
        return selectedSession.latestTake
    }

    private var reportCache: (takeID: UUID, value: String)?

    var report: String {
        guard let take = selectedTake else { return "" }
        if let reportCache, reportCache.takeID == take.id { return reportCache.value }
        let value = ReportFormatter.makeReport(session: take)
        reportCache = (take.id, value)
        return value
    }
    var storageLocation: URL { store.rootURL }
    var isMimicAlong: Bool { mimicAlong }
    var isMimicWorkspace: Bool {
        guard selectedSession?.mode == .mimic else { return false }
        switch destination {
        case .studio, .practice: return true
        case .create, .take, .sessions, .insights: return false
        }
    }
    var hasPendingMimicWork: Bool {
        pendingMimicSessionID == selectedSessionID && (pendingMimicTake != nil || pendingMimicAudio != nil)
    }
    var totalTakeCount: Int { sessions.reduce(0) { $0 + $1.takeCount } }
    var totalRecordedDuration: Double { sessions.reduce(0) { $0 + $1.totalDuration } }

    func navigate(to destination: AppDestination) {
        if isRecording || isAnalyzing || mimicPhase != .ready { return }
        stopPlayback()
        self.destination = destination
    }

    func navigate(to section: NavigationSection) {
        switch section {
        case .studio: navigate(to: AppDestination.studio)
        case .sessions: navigate(to: AppDestination.sessions)
        case .insights: navigate(to: AppDestination.insights)
        }
    }

    @discardableResult
    func createSession(name: String, mode: PracticeMode, prompt: String, keepsRecordings: Bool) -> UUID {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = CoachingSession(
            name: cleanName.isEmpty ? "Untitled Practice" : cleanName,
            mode: mode,
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            keepsRecordings: mode == .mimic ? true : keepsRecordings
        )
        sessions.insert(session, at: 0)
        selectedSessionID = session.id
        selectedTakeID = nil
        persist()
        destination = .practice(session.id)
        return session.id
    }

    func startQuickPractice() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d · h:mm a"
        createSession(name: "Quick Practice · \(formatter.string(from: Date()))", mode: .general, prompt: "", keepsRecordings: true)
    }

    func resumeSession(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        selectedSessionID = id
        selectedTakeID = session.latestTake?.id
        navigate(to: .practice(id))
        if session.mode == .mimic { mimicShowingResult = session.latestTake != nil }
    }

    func openTake(sessionID: UUID, takeID: UUID? = nil) {
        guard let session = sessions.first(where: { $0.id == sessionID }),
              let take = takeID.flatMap({ id in session.takes.first(where: { $0.id == id }) }) ?? session.latestTake
        else { return }
        selectedSessionID = sessionID
        selectedTakeID = take.id
        navigate(to: .take(sessionID, take.id))
    }

    func selectTake(_ takeID: UUID) {
        guard let selectedSession, selectedSession.takes.contains(where: { $0.id == takeID }) else { return }
        stopPlayback()
        selectedTakeID = takeID
        if selectedSession.mode == .mimic { mimicShowingResult = true }
        mimicSelectedWord = nil
        if case .take(let sessionID, _) = destination { destination = .take(sessionID, takeID) }
    }

    func renameSession(_ id: UUID, to name: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        sessions[index].name = cleanName
        sessions[index].updatedAt = Date()
        sortSessions()
        persist()
    }

    func deleteSession(_ id: UUID) {
        if pendingMimicSessionID == id {
            errorMessage = "This session has an unsaved recording. Retry saving it or reveal the audio file before deleting the session."
            return
        }
        stopPlayback()
        let previousSessions = sessions
        let previousSessionID = selectedSessionID
        let previousTakeID = selectedTakeID
        let previousDestination = destination
        sessions.removeAll { $0.id == id }
        if selectedSessionID == id {
            selectedSessionID = sessions.first?.id
            selectedTakeID = sessions.first?.latestTake?.id
            destination = .sessions
        }
        guard persist() else {
            sessions = previousSessions
            selectedSessionID = previousSessionID
            selectedTakeID = previousTakeID
            destination = previousDestination
            return
        }
        do {
            try store.deleteSessionData(sessionID: id)
            toastMessage = "Session and recordings removed"
        } catch {
            errorMessage = "The session was removed from the library, but its recording folder could not be deleted. \(error.localizedDescription)"
        }
    }

    func deleteTake(_ takeID: UUID) {
        stopPlayback()
        guard let sessionID = selectedSessionID,
              let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let takeIndex = sessions[sessionIndex].takes.firstIndex(where: { $0.id == takeID })
        else { return }

        let previousSessions = sessions
        let previousTakeID = selectedTakeID
        let previousDestination = destination
        let removed = sessions[sessionIndex].takes.remove(at: takeIndex)
        sessions[sessionIndex].mimicAttemptStyles?.removeValue(forKey: takeID)
        let remainingCount = sessions[sessionIndex].takes.count
        sessions[sessionIndex].updatedAt = Date()

        if selectedTakeID == takeID {
            let remaining = sessions[sessionIndex].takes
            selectedTakeID = remaining.indices.contains(takeIndex) ? remaining[takeIndex].id : remaining.last?.id
            if case .take = destination {
                if let selectedTakeID {
                    destination = .take(sessionID, selectedTakeID)
                } else {
                    destination = .practice(sessionID)
                }
            }
        }

        sortSessions()
        guard persist() else {
            sessions = previousSessions
            selectedTakeID = previousTakeID
            destination = previousDestination
            return
        }

        try? FileManager.default.removeItem(at: removed.audioURL)
        if reportCache?.takeID == takeID { reportCache = nil }
        if remainingCount == 0 { mimicShowingResult = false }
        toastMessage = remainingCount == 0
            ? "Take removed. Record another when you are ready."
            : "Take removed"
    }

    func recordButtonPressed() {
        if selectedSession?.mode == .mimic {
            if isRecording { stopRecording() }
            else { startMimicPractice() }
            return
        }
        guard !isAnalyzing, !isRequestingPermission else { return }
        isRecording ? stopRecording() : requestPermissionAndRecord()
    }

    func importClip() {
        guard !isRecording, !isAnalyzing, !isRequestingPermission, ensureActiveSession(),
              selectedSession?.mode != .mimic, let sessionID = selectedSessionID else { return }

        let panel = NSOpenPanel()
        panel.title = "Import an audio or video clip"
        panel.message = "Voice Coach will extract the audio and save an analyzed copy in this session."
        panel.prompt = "Import clip"
        panel.allowedContentTypes = AudioImportService.allowedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        let takeID = UUID()
        let source = AudioImportService.source(for: sourceURL)
        do {
            let destinationURL = try store.importedAudioURL(
                sessionID: sessionID,
                takeID: takeID,
                fileExtension: "wav"
            )
            isAnalyzing = true
            errorMessage = nil
            toastMessage = nil
            transcriptionNotice = nil

            Task {
                do {
                    try await AudioImportService.prepareAudio(from: sourceURL, to: destinationURL)
                    analyze(url: destinationURL, takeID: takeID, source: source)
                } catch {
                    try? FileManager.default.removeItem(at: destinationURL)
                    errorMessage = "Import failed: \(error.localizedDescription)"
                    isAnalyzing = false
                }
            }
        } catch {
            errorMessage = "Voice Coach could not create local storage for this import. \(error.localizedDescription)"
        }
    }

    func copyReport() { copyToPasteboard(report, message: "Word-level voice data copied") }

    func copyAICoachPrompt() {
        guard let session = selectedSession, !report.isEmpty else { return }
        let coachPrompt = """
        You are an expert speech coach. Assess the objective acoustic measurements for the take below from the session “\(session.name)”. Explain the strongest delivery patterns, identify the two highest-impact improvements, and give three specific exercises for the next take. Treat HNR and CPP as acoustic proxies, not medical measurements. Do not invent observations that are not supported by the data.

        VOICE COACH JSON
        \(report)
        """
        copyToPasteboard(coachPrompt, message: "AI coach prompt copied")
    }

    private func copyToPasteboard(_ value: String, message: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        toastMessage = message
    }

    func playCurrent() {
        guard !isRecording, !isAnalyzing else { return }
        if isPlaying {
            pausePlayback()
            return
        }
        guard let take = selectedTake else { return }
        let duration = take.result.metrics.duration
        let startTime = playbackTime >= max(duration - 0.05, 0) ? 0 : playbackTime
        do {
            try recorder.play(url: take.audioURL, from: startTime)
            playbackTime = startTime
            isPlaying = true
            startPlaybackTimer()
        } catch {
            errorMessage = "This recording could not be played. Its audio file may have been moved. \(error.localizedDescription)"
        }
    }

    func pausePlayback() {
        recorder.pausePlayback()
        stopPlaybackTimer()
        isPlaying = false
    }

    func stopPlayback() {
        recorder.stopPlayback()
        stopPlaybackTimer()
        isPlaying = false
        playbackTime = 0
        mimicPlaybackEnd = nil
        clearMimicDifferenceState()
        if mimicPhase == .playingReference {
            mimicShouldRecordAfterPlayback = false
            mimicPhase = .ready
        }
    }

    func seek(to time: TimeInterval, autoplay: Bool = false) {
        guard let take = selectedTake, !isRecording, !isAnalyzing else { return }
        let clamped = max(0, min(time, take.result.metrics.duration))
        playbackTime = clamped
        if isPlaying {
            recorder.seek(to: clamped)
        } else if autoplay {
            do {
                try recorder.play(url: take.audioURL, from: clamped)
                isPlaying = true
                startPlaybackTimer()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func exportCurrent() {
        guard let take = selectedTake else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose where to export this Voice Coach take"
        panel.prompt = "Export Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let folder = parent.appendingPathComponent("Voice Coach \(formatter.string(from: take.createdAt))", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            let extensionName = take.audioURL.pathExtension.isEmpty ? "m4a" : take.audioURL.pathExtension
            try FileManager.default.copyItem(at: take.audioURL, to: folder.appendingPathComponent("recording.\(extensionName)"))
            try report.write(to: folder.appendingPathComponent("voice-report.json"), atomically: true, encoding: .utf8)
            toastMessage = "Exported audio and report"
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch { errorMessage = "Could not export the take: \(error.localizedDescription)" }
    }

    func revealStorage() { NSWorkspace.shared.activateFileViewerSelecting([storageLocation]) }

    func refreshTranscriptionSetupStatus() {
        guard !transcriptionSetupStatus.isBusy else { return }
        transcriptionSetupStatus = TranscriptionSetupService.currentStatus()
    }

    func refreshSystemTranscriptionStatus() {
        guard !systemTranscriptionStatus.isBusy else { return }
        systemTranscriptionStatusTask?.cancel()
        systemTranscriptionStatusTask = Task { @MainActor [weak self] in
            let status = await AppleSpeechTranscriber.currentStatus()
            guard !Task.isCancelled else { return }
            self?.systemTranscriptionStatus = status
        }
    }

    func setTranscriptionEngine(_ engine: TranscriptionEnginePreference) {
        transcriptionEngine = engine
        engine.save()
        toastMessage = "Transcription engine set to \(engine.title)"
    }

    func ensureSystemTranscriptionAssets() {
        guard !systemTranscriptionStatus.isBusy else { return }
        guard !isRecording, !isAnalyzing else {
            errorMessage = "Finish recording or analysis before downloading speech models."
            return
        }
        if case .ready = systemTranscriptionStatus {
            toastMessage = "System transcription is already ready"
            return
        }

        let locale: String
        if case .needsDownload(let identifier) = systemTranscriptionStatus {
            locale = identifier
        } else {
            locale = Locale.current.identifier
        }

        systemAssetInstallTask?.cancel()
        systemTranscriptionStatus = .downloading(localeIdentifier: locale)
        systemAssetInstallTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await AppleSpeechTranscriber.ensureAssets()
                guard !Task.isCancelled else { return }
                systemTranscriptionStatus = await AppleSpeechTranscriber.currentStatus()
                if systemTranscriptionStatus.isReady {
                    toastMessage = "System transcription is ready"
                }
            } catch is CancellationError {
                refreshSystemTranscriptionStatus()
            } catch {
                systemTranscriptionStatus = .unavailable(error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
    }

    func startTranscriptionSetup() {
        guard !transcriptionSetupStatus.isBusy else { return }
        guard !isRecording, !isAnalyzing else {
            errorMessage = "Finish recording or analysis before downloading transcription."
            return
        }

        transcriptionSetupTask?.cancel()
        transcriptionSetupStatus = .installing(.preparing)
        transcriptionSetupTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await TranscriptionSetupService().installOrUpdate { phase in
                    Task { @MainActor in
                        self.transcriptionSetupStatus = .installing(phase)
                    }
                }
                guard !Task.isCancelled else { return }
                transcriptionSetupStatus = TranscriptionSetupService.currentStatus()
                if transcriptionSetupStatus.isReady {
                    toastMessage = "Parakeet transcription is ready"
                }
            } catch is CancellationError {
                refreshTranscriptionSetupStatus()
            } catch {
                transcriptionSetupStatus = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
    }

    func revealTranscriptionInstall() {
        if let managed = try? TranscriptionSetupService.managedRuntimePrefixURL(),
           FileManager.default.fileExists(atPath: managed.path) {
            NSWorkspace.shared.activateFileViewerSelecting([managed])
            return
        }
        if case .ready(let path, _) = transcriptionSetupStatus {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([storageLocation])
    }

    private func requestPermissionAndRecord() {
        guard ensureActiveSession() else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: beginRecording()
        case .notDetermined:
            isRequestingPermission = true
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.isRequestingPermission = false
                    if granted { self.beginRecording() }
                    else { self.errorMessage = RecorderError.microphoneDenied.localizedDescription }
                }
            }
        default: errorMessage = RecorderError.microphoneDenied.localizedDescription
        }
    }

    private func ensureActiveSession() -> Bool {
        if let selectedSessionID, sessions.contains(where: { $0.id == selectedSessionID }) { return true }
        startQuickPractice()
        return selectedSessionID != nil
    }

    private func beginRecording() {
        guard let sessionID = selectedSessionID else { return }
        if !mimicAlong {
            recorder.stopPlayback()
            isPlaying = false
        }
        do {
            let takeID = UUID()
            let url = try store.recordingURL(sessionID: sessionID, takeID: takeID)
            try recorder.start(url: url)
            recordingURL = url
            recordingTakeID = takeID
            startedAt = Date()
            elapsed = 0
            liveLevel = -80
            isRecording = true
            if sessions.first(where: { $0.id == sessionID })?.mode == .mimic {
                mimicPhase = .recording
            }
            isAnalyzing = false
            errorMessage = nil
            toastMessage = nil
            transcriptionNotice = nil
            startTimer()
            if mimicAlong, let reference = selectedSession?.mimicReference {
                do {
                    recorder.playbackVolume = Float(mimicReferenceVolume)
                    try recorder.play(url: reference.take.audioURL)
                    mimicPlaybackSource = .reference
                    isPlaying = true
                    startPlaybackTimer()
                } catch {
                    recorder.stop()
                    timer?.invalidate()
                    timer = nil
                    isRecording = false
                    mimicPhase = .ready
                    errorMessage = "Could not play the reference while recording. \(error.localizedDescription)"
                    if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
                    recordingURL = nil
                    recordingTakeID = nil
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func stopRecording() {
        mimicCountInTask?.cancel()
        let wasMimic = selectedSession?.mode == .mimic
        if wasMimic {
            recorder.stopPlayback()
            stopPlaybackTimer()
            isPlaying = false
            mimicAlong = false
        }
        recorder.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        if wasMimic { mimicPhase = .analyzing }
        guard elapsed >= 0.6, let url = recordingURL, let takeID = recordingTakeID else {
            errorMessage = "Record at least one second so there is enough voice to analyze."
            if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
            recordingURL = nil
            recordingTakeID = nil
            mimicPhase = .ready
            return
        }
        analyze(url: url, takeID: takeID)
    }

    private func analyze(url: URL, takeID: UUID, source: TakeSource = .recorded) {
        isAnalyzing = true
        let preferredEngine = transcriptionEngine
        Task {
            do {
                let acoustic = try await Task.detached(priority: .userInitiated) {
                    try AudioAnalyzer().analyze(url: url)
                }.value

                var transcription: TranscriptionResult?
                var words: [WordAnalysis] = []
                var notice: String?
                do {
                    let outcome = try await TranscriptionService(preferredEngine: preferredEngine)
                        .transcribe(url: url)
                    transcription = outcome.result
                    words = WordAcousticAnalyzer().analyze(
                        transcription: outcome.result,
                        result: acoustic
                    )
                    notice = outcome.notice
                } catch {
                    notice = error.localizedDescription
                }

                let take = PracticeSession(
                    id: takeID,
                    audioURL: url,
                    source: source,
                    result: acoustic,
                    transcription: transcription,
                    words: words
                )
                append(take)
                transcriptionNotice = notice
            } catch {
                errorMessage = "Analysis failed: \(error.localizedDescription)"
                if selectedSession?.mode == .mimic {
                    pendingMimicAudio = (url, takeID)
                    pendingMimicSessionID = selectedSessionID
                }
            }
            isAnalyzing = false
            mimicPhase = .ready
            recordingURL = nil
            recordingTakeID = nil
        }
    }

    private func append(_ take: PracticeSession) {
        guard let selectedSessionID, let index = sessions.firstIndex(where: { $0.id == selectedSessionID }) else { return }
        let previousSessions = sessions
        var recordingsToReplace: [URL] = []
        if sessions[index].keepsRecordings || sessions[index].mode == .mimic {
            sessions[index].takes.append(take)
            if sessions[index].mode == .mimic {
                if sessions[index].mimicAttemptStyles == nil { sessions[index].mimicAttemptStyles = [:] }
                sessions[index].mimicAttemptStyles?[take.id] = sessions[index].mimicStyle ?? .listenAndRepeat
            }
        } else {
            recordingsToReplace = sessions[index].takes.map(\.audioURL)
            sessions[index].takes = [take]
        }
        sessions[index].updatedAt = Date()
        selectedTakeID = take.id
        sortSessions()
        guard persist() else {
            sessions = previousSessions
            selectedTakeID = previousSessions.first(where: { $0.id == selectedSessionID })?.latestTake?.id
            if sessions[index].mode == .mimic {
                pendingMimicTake = take
                pendingMimicSessionID = selectedSessionID
                errorMessage = "The recording is still on this Mac but could not be added to the library. Retry Save or reveal the audio file."
            }
            return
        }
        if pendingMimicSessionID == selectedSessionID {
            pendingMimicTake = nil
            pendingMimicAudio = nil
            pendingMimicSessionID = nil
        }
        for url in recordingsToReplace where url != take.audioURL {
            try? FileManager.default.removeItem(at: url)
        }
        toastMessage = "\(take.takeSource.title) saved on this Mac"
        if sessions[index].mode == .mimic {
            mimicShowingResult = true
            destination = .practice(selectedSessionID)
        } else {
            destination = .take(selectedSessionID, take.id)
        }
    }

    private func sortSessions() { sessions.sort { $0.updatedAt > $1.updatedAt } }

    @discardableResult
    private func persist() -> Bool {
        do {
            try store.save(sessions)
            return true
        } catch {
            errorMessage = "Voice Coach could not save your session library. \(error.localizedDescription)"
            return false
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = Date().timeIntervalSince(self.startedAt ?? Date())
                self.liveLevel = Double(self.recorder.peakLevel())
                if self.elapsed >= 90 { self.stopRecording() }
            }
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.playbackTime = self.recorder.currentTime
                if let end = self.mimicPlaybackEnd, self.playbackTime >= end {
                    self.recorder.stopPlayback()
                    self.finishMimicPlayback()
                }
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    func chooseMimicReference() {
        guard !mimicIsPreparing, !isRecording else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a voice to mimic"
        panel.message = "Audio stays on this Mac. You can select a short excerpt next."
        panel.prompt = "Use Clip"
        panel.allowedContentTypes = AudioImportService.allowedContentTypes
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        cancelMimicPreparation()
        let id = UUID()
        mimicPreparationID = id
        mimicIsPreparing = true
        errorMessage = nil
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("voice-coach-mimic-\(id).wav")
        Task {
            do {
                try await AudioImportService.prepareAudio(from: sourceURL, to: staged)
                let overview = try await Task.detached(priority: .userInitiated) {
                    try AudioImportService.waveform(from: staged)
                }.value
                guard mimicPreparationID == id else {
                    try? FileManager.default.removeItem(at: staged)
                    return
                }
                mimicDraft = MimicReferenceDraft(
                    id: id, url: staged,
                    sourceName: sourceURL.deletingPathExtension().lastPathComponent,
                    duration: overview.duration, peaks: overview.peaks,
                    source: AudioImportService.source(for: sourceURL)
                )
                mimicIsPreparing = false
            } catch {
                try? FileManager.default.removeItem(at: staged)
                if mimicPreparationID == id {
                    mimicIsPreparing = false
                    errorMessage = "Could not prepare the reference: \(error.localizedDescription)"
                }
            }
        }
    }

    func cancelMimicPreparation() {
        mimicPreparationID = nil
        mimicIsPreparing = false
        stopPlayback()
        if let url = mimicDraft?.url { try? FileManager.default.removeItem(at: url) }
        mimicDraft = nil
    }

    func createMimicSession(name: String, start: Double, end: Double) {
        guard let draft = mimicDraft, !mimicIsPreparing,
              start >= 0, end <= draft.duration + 0.02, end - start >= 1,
              let activeID = mimicPreparationID else { return }
        mimicIsPreparing = true
        stopPlayback()
        let sessionID = UUID()
        let referenceID = UUID()
        let preferredEngine = transcriptionEngine
        do {
            let destinationURL = try store.referenceURL(sessionID: sessionID)
            Task {
                do {
                    let acoustic = try await Task.detached(priority: .userInitiated) {
                        try AudioImportService.trimAudio(from: draft.url, to: destinationURL, start: start, end: end)
                        return try AudioAnalyzer().analyze(url: destinationURL)
                    }.value
                    var transcription: TranscriptionResult?
                    var words: [WordAnalysis] = []
                    do {
                        let outcome = try await TranscriptionService(preferredEngine: preferredEngine).transcribe(url: destinationURL)
                        transcription = outcome.result
                        words = WordAcousticAnalyzer().analyze(transcription: outcome.result, result: acoustic)
                    } catch {
                        transcriptionNotice = error.localizedDescription
                    }
                    guard mimicPreparationID == activeID else {
                        try? store.deleteSessionData(sessionID: sessionID)
                        return
                    }
                    let referenceTake = PracticeSession(
                        id: referenceID, audioURL: destinationURL,
                        source: draft.source, result: acoustic,
                        transcription: transcription, words: words
                    )
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let session = CoachingSession(
                        id: sessionID,
                        name: cleanName.isEmpty ? draft.sourceName : cleanName,
                        mode: .mimic, prompt: "", keepsRecordings: true,
                        mimicReference: MimicReference(
                            sourceName: draft.sourceName, take: referenceTake,
                            sourceStart: start, sourceEnd: end
                        ), mimicStyle: .listenAndRepeat, mimicAttemptStyles: [:]
                    )
                    sessions.insert(session, at: 0)
                    guard persist() else {
                        sessions.removeAll { $0.id == sessionID }
                        try? store.deleteSessionData(sessionID: sessionID)
                        mimicIsPreparing = false
                        return
                    }
                    selectedSessionID = sessionID
                    selectedTakeID = nil
                    mimicShowingResult = false
                    destination = .practice(sessionID)
                    cancelMimicPreparation()
                } catch {
                    try? store.deleteSessionData(sessionID: sessionID)
                    if mimicPreparationID == activeID {
                        mimicIsPreparing = false
                        errorMessage = "Could not create Mimic session: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            mimicIsPreparing = false
            errorMessage = "Could not create reference storage: \(error.localizedDescription)"
        }
    }

    func updateMimicStyle(_ style: MimicStyle) {
        guard !isRecording, !isAnalyzing, mimicPhase == .ready,
              let id = selectedSessionID, let index = sessions.firstIndex(where: { $0.id == id }),
              sessions[index].mode == .mimic else { return }
        let prior = sessions[index].mimicStyle
        sessions[index].mimicStyle = style
        if !persist() { sessions[index].mimicStyle = prior }
    }

    func startMimicPractice(skipReference: Bool = false) {
        guard !isRecording, !isPlaying, !isAnalyzing, !isRequestingPermission,
              mimicPhase == .ready, !hasPendingMimicWork,
              let reference = selectedSession?.mimicReference else { return }
        guard FileManager.default.fileExists(atPath: reference.take.audioURL.path) else {
            errorMessage = "The reference audio is missing. Its saved attempts are still available in Take Analysis."
            return
        }
        let begin: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.mimicShowingResult = false
            if self.selectedSession?.mimicStyle == .speakAlong || skipReference {
                self.startMimicCountIn()
            } else {
                self.mimicShouldRecordAfterPlayback = true
                self.mimicPhase = .playingReference
                self.playMimicReference()
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: begin()
        case .notDetermined:
            isRequestingPermission = true
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.isRequestingPermission = false
                    if granted { begin() }
                    else { self.errorMessage = RecorderError.microphoneDenied.localizedDescription }
                }
            }
        default: errorMessage = RecorderError.microphoneDenied.localizedDescription
        }
    }

    func cancelMimicCountIn() {
        guard case .countIn = mimicPhase else { return }
        mimicCountInTask?.cancel()
        mimicPhase = .ready
    }

    private func startMimicCountIn() {
        mimicPhase = .countIn(2)
        mimicCountInTask?.cancel()
        mimicCountInTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.mimicPhase = .countIn(1)
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self.mimicAlong = self.selectedSession?.mimicStyle == .speakAlong
            self.beginRecording()
            if !self.isRecording { self.mimicPhase = .ready }
        }
    }

    func playMimicReference(range: ClosedRange<Double>? = nil) {
        guard let reference = selectedSession?.mimicReference, !isRecording else { return }
        let bounds = range ?? 0...reference.take.result.metrics.duration
        clearMimicDifferenceState()
        playMimicSegment(url: reference.take.audioURL, source: .reference, start: bounds.lowerBound, end: bounds.upperBound)
    }

    func playMimicDraft(start: Double, end: Double) {
        guard let mimicDraft, !mimicIsPreparing else { return }
        clearMimicDifferenceState()
        playMimicSegment(url: mimicDraft.url, source: .reference, start: start, end: end)
    }

    func playMimicAttempt(range: ClosedRange<Double>? = nil) {
        guard let take = selectedTake, !isRecording else { return }
        let bounds = range ?? 0...take.result.metrics.duration
        clearMimicDifferenceState()
        playMimicSegment(url: take.audioURL, source: .attempt, start: bounds.lowerBound, end: bounds.upperBound)
    }

    func seekMimic(source: MimicPlaybackSource, to time: Double) {
        guard !isRecording, !isAnalyzing, mimicPhase == .ready else { return }
        let take = source == .reference ? selectedSession?.mimicReference?.take : selectedTake
        guard let take else { return }
        let duration = take.result.metrics.duration
        guard duration > 0 else { return }
        let start = min(max(0, time), max(0, duration - 0.05))
        clearMimicDifferenceState()
        playMimicSegment(url: take.audioURL, source: source, start: start, end: duration)
    }

    func playMimicDifference(_ observation: MimicObservation?) {
        guard let reference = selectedSession?.mimicReference, let take = selectedTake, !isRecording else { return }
        stopPlayback()
        let ref = observation?.referenceRange ?? 0...reference.take.result.metrics.duration
        let own = observation?.attemptRange ?? 0...take.result.metrics.duration
        mimicNextSegment = (take.audioURL, own.lowerBound, own.upperBound)
        mimicHearingDifference = true
        playMimicSegment(url: reference.take.audioURL, source: .reference, start: ref.lowerBound, end: ref.upperBound)
    }

    func retryPendingMimicWork() {
        guard hasPendingMimicWork else { return }
        if let pendingMimicTake {
            append(pendingMimicTake)
        } else if let pendingMimicAudio {
            analyze(url: pendingMimicAudio.url, takeID: pendingMimicAudio.id)
        }
    }

    func revealPendingMimicAudio() {
        let url = pendingMimicTake?.audioURL ?? pendingMimicAudio?.url
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func stepMimicTake(by delta: Int) {
        guard let session = selectedSession, session.mode == .mimic,
              !isRecording, mimicPhase == .ready,
              let current = selectedTakeID.flatMap({ id in session.takes.firstIndex(where: { $0.id == id }) }),
              session.takes.indices.contains(current + delta) else { return }
        selectTake(session.takes[current + delta].id)
    }

    func toggleMimicPlayback() {
        guard isMimicWorkspace, !isRecording else { return }
        if mimicPhase == .playingReference {
            stopPlayback()
            return
        }
        guard mimicPhase == .ready else { return }
        if isPlaying {
            pausePlayback()
            return
        }
        let source: MimicPlaybackSource = mimicShowingResult ? mimicPlaybackSource : .reference
        let take = source == .reference ? selectedSession?.mimicReference?.take : selectedTake
        guard let take else { return }
        let start = source == mimicPlaybackSource ? playbackTime : 0
        if start <= 0 || start >= take.result.metrics.duration - 0.05 {
            seekMimic(source: source, to: 0)
            return
        }
        do {
            recorder.playbackVolume = source == .reference ? Float(mimicReferenceVolume) : 1
            try recorder.play(url: take.audioURL, from: start)
            mimicPlaybackSource = source
            mimicPlaybackEnd = mimicPlaybackEnd ?? take.result.metrics.duration
            isPlaying = true
            startPlaybackTimer()
        } catch { errorMessage = "This clip could not be played: \(error.localizedDescription)" }
    }

    private func playMimicSegment(url: URL, source: MimicPlaybackSource, start: Double, end: Double) {
        guard !isRecording, end > start else { return }
        recorder.stopPlayback()
        stopPlaybackTimer()
        do {
            recorder.playbackVolume = source == .reference ? Float(mimicReferenceVolume) : 1
            try recorder.play(url: url, from: start)
            mimicPlaybackSource = source
            mimicPlaybackEnd = end
            isPlaying = true
            playbackTime = start
            startPlaybackTimer()
        } catch {
            clearMimicDifferenceState()
            mimicShouldRecordAfterPlayback = false
            mimicPhase = .ready
            errorMessage = "This clip could not be played: \(error.localizedDescription)"
        }
    }

    private func clearMimicDifferenceState() {
        mimicNextSegment = nil
        mimicHearingDifference = false
    }

    private func finishMimicPlayback() {
        stopPlaybackTimer()
        isPlaying = false
        playbackTime = 0
        mimicPlaybackEnd = nil
        if let next = mimicNextSegment {
            mimicNextSegment = nil
            playMimicSegment(url: next.url, source: .attempt, start: next.start, end: next.end)
            return
        }
        mimicHearingDifference = false
        if mimicShouldRecordAfterPlayback {
            mimicShouldRecordAfterPlayback = false
            startMimicCountIn()
        } else if mimicAlong && isRecording {
            mimicCountInTask?.cancel()
            mimicCountInTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, !Task.isCancelled, self.isRecording else { return }
                self.stopRecording()
            }
        } else if mimicPhase == .playingReference {
            mimicPhase = .ready
        }
    }
}
