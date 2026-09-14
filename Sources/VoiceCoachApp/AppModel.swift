import AppKit
import AVFoundation
import Foundation
import VoiceCoachCore

private struct CompletedAnalysis: Sendable {
    let result: AnalysisResult
    let transcription: TranscriptionResult?
    let words: [WordAnalysis]
    let transcriptionNotice: String?
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

    private let recorder = AudioRecorder()
    private let store: SessionStore
    private var timer: Timer?
    private var playbackTimer: Timer?
    private var recordingURL: URL?
    private var recordingTakeID: UUID?
    private var startedAt: Date?

    init(storageRoot: URL? = nil, loadPersistedData: Bool = true) {
        do {
            store = try SessionStore(rootURL: storageRoot)
        } catch {
            fatalError("Voice Coach could not open local storage: \(error.localizedDescription)")
        }

        recorder.onPlaybackFinished = { [weak self] in
            guard let self else { return }
            self.stopPlaybackTimer()
            self.isPlaying = false
            self.playbackTime = 0
        }

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

    var previousTake: PracticeSession? {
        guard let selectedSession, let selectedTake else { return nil }
        guard let index = selectedSession.takes.firstIndex(where: { $0.id == selectedTake.id }), index > 0 else { return nil }
        return selectedSession.takes[index - 1]
    }

    private var cachedReportTakeID: UUID?
    private var cachedReport = ""
    private var cachedCompactReportTakeID: UUID?
    private var cachedCompactReport = ""

    var report: String {
        guard let take = selectedTake else { return "" }
        if cachedReportTakeID == take.id { return cachedReport }
        cachedReport = ReportFormatter.makeReport(session: take)
        cachedReportTakeID = take.id
        return cachedReport
    }

    var compactReport: String {
        guard let take = selectedTake else { return "" }
        if cachedCompactReportTakeID == take.id { return cachedCompactReport }
        cachedCompactReport = ReportFormatter.makeCompactReport(session: take)
        cachedCompactReportTakeID = take.id
        return cachedCompactReport
    }
    var storageLocation: URL { store.rootURL }
    var totalTakeCount: Int { sessions.reduce(0) { $0 + $1.takeCount } }
    var totalRecordedDuration: Double { sessions.reduce(0) { $0 + $1.totalDuration } }

    func navigate(to destination: AppDestination) {
        if isRecording { return }
        stopPlayback()
        self.destination = destination
    }

    func navigate(to section: NavigationSection) {
        switch section {
        case .studio: navigate(to: AppDestination.studio)
        case .sessions: navigate(to: AppDestination.sessions)
        case .insights: navigate(to: AppDestination.insights)
        case .settings: navigate(to: AppDestination.settings)
        }
    }

    @discardableResult
    func createSession(name: String, mode: PracticeMode, prompt: String, keepsRecordings: Bool) -> UUID {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = CoachingSession(
            name: cleanName.isEmpty ? "Untitled Practice" : cleanName,
            mode: mode,
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            keepsRecordings: keepsRecordings
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
    }

    func review(sessionID: UUID, takeID: UUID? = nil) {
        guard let session = sessions.first(where: { $0.id == sessionID }),
              let take = takeID.flatMap({ id in session.takes.first(where: { $0.id == id }) }) ?? session.latestTake
        else { return }
        selectedSessionID = sessionID
        selectedTakeID = take.id
        navigate(to: .review(sessionID, take.id))
    }

    func selectTake(_ takeID: UUID) {
        guard let selectedSession, selectedSession.takes.contains(where: { $0.id == takeID }) else { return }
        stopPlayback()
        selectedTakeID = takeID
        if case .review(let sessionID, _) = destination { destination = .review(sessionID, takeID) }
    }

    func selectAdjacentTake(offset: Int) {
        guard let selectedSession, let selectedTake,
              let index = selectedSession.takes.firstIndex(where: { $0.id == selectedTake.id })
        else { return }
        let target = index + offset
        guard selectedSession.takes.indices.contains(target) else { return }
        selectTake(selectedSession.takes[target].id)
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

    func recordButtonPressed() {
        guard !isAnalyzing, !isRequestingPermission else { return }
        isRecording ? stopRecording() : requestPermissionAndRecord()
    }

    func importClip() {
        guard !isRecording, !isAnalyzing, !isRequestingPermission, ensureActiveSession(), let sessionID = selectedSessionID else { return }

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

    func copyReport() { copyJSON(report, message: "Word-level voice data copied") }
    func copyCompactReport() { copyJSON(compactReport, message: "Compact voice data copied") }

    private func copyJSON(_ value: String, message: String) {
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
        recorder.stopPlayback()
        isPlaying = false
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
            isAnalyzing = false
            errorMessage = nil
            toastMessage = nil
            transcriptionNotice = nil
            startTimer()
        } catch { errorMessage = error.localizedDescription }
    }

    private func stopRecording() {
        recorder.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        guard elapsed >= 0.6, let url = recordingURL, let takeID = recordingTakeID else {
            errorMessage = "Record at least one second so there is enough voice to analyze."
            return
        }
        analyze(url: url, takeID: takeID)
    }

    private func analyze(url: URL, takeID: UUID, source: TakeSource = .recorded) {
        isAnalyzing = true
        Task {
            do {
                let completed = try await Task.detached(priority: .userInitiated) { () throws -> CompletedAnalysis in
                    let result = try AudioAnalyzer().analyze(url: url)
                    do {
                        let transcription = try NemoSpeechTranscriber().transcribe(url: url)
                        return CompletedAnalysis(result: result, transcription: transcription, words: WordAcousticAnalyzer().analyze(transcription: transcription, result: result), transcriptionNotice: nil)
                    } catch {
                        return CompletedAnalysis(result: result, transcription: nil, words: [], transcriptionNotice: error.localizedDescription)
                    }
                }.value
                let take = PracticeSession(id: takeID, audioURL: url, source: source, result: completed.result, transcription: completed.transcription, words: completed.words)
                append(take)
                transcriptionNotice = completed.transcriptionNotice
            } catch { errorMessage = "Analysis failed: \(error.localizedDescription)" }
            isAnalyzing = false
            recordingURL = nil
            recordingTakeID = nil
        }
    }

    private func append(_ take: PracticeSession) {
        guard let selectedSessionID, let index = sessions.firstIndex(where: { $0.id == selectedSessionID }) else { return }
        let previousSessions = sessions
        var recordingsToReplace: [URL] = []
        if sessions[index].keepsRecordings {
            sessions[index].takes.append(take)
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
            return
        }
        for url in recordingsToReplace where url != take.audioURL {
            try? FileManager.default.removeItem(at: url)
        }
        toastMessage = "\(take.takeSource.title) saved on this Mac"
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
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
}
