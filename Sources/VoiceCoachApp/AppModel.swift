import AppKit
import AVFoundation
import Foundation
import VoiceCoachCore

@MainActor
final class AppModel: ObservableObject {
    @Published var isRecording = false
    @Published var isAnalyzing = false
    @Published var isRequestingPermission = false
    @Published var isPlaying = false
    @Published var elapsed: TimeInterval = 0
    @Published var liveLevel: Double = -80
    @Published var session: PracticeSession?
    @Published var errorMessage: String?
    @Published var exportMessage: String?

    private let recorder = AudioRecorder()
    private var timer: Timer?
    private var recordingURL: URL?
    private var startedAt: Date?

    init() {
        recorder.onPlaybackFinished = { [weak self] in self?.isPlaying = false }
    }

    var report: String {
        guard let session else { return "" }
        return ReportFormatter.makeReport(session: session)
    }

    func recordButtonPressed() {
        guard !isAnalyzing, !isRequestingPermission else { return }
        if isRecording {
            stopRecording()
        } else {
            requestPermissionAndRecord()
        }
    }

    func copyReport() {
        guard !report.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        exportMessage = "Structured voice data copied"
    }

    func playCurrent() {
        guard !isRecording, !isAnalyzing else { return }
        if isPlaying {
            recorder.stopPlayback()
            isPlaying = false
            return
        }
        guard let url = session?.audioURL else { return }
        do {
            try recorder.play(url: url)
            isPlaying = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportCurrent() {
        guard let session else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose where to export this voice-coach session"
        panel.prompt = "Export Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let stamp = formatter.string(from: session.createdAt)
        let folder = parent.appendingPathComponent("Voice Coach \(stamp)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            let audioDestination = folder.appendingPathComponent("recording.wav")
            try FileManager.default.copyItem(at: session.audioURL, to: audioDestination)
            try report.write(to: folder.appendingPathComponent("voice-report.json"), atomically: true, encoding: .utf8)
            exportMessage = "Exported recording and report"
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            errorMessage = "Could not export the session: \(error.localizedDescription)"
        }
    }

    private func requestPermissionAndRecord() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecording()
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
        default:
            errorMessage = RecorderError.microphoneDenied.localizedDescription
        }
    }

    private func beginRecording() {
        recorder.stopPlayback()
        isPlaying = false
        do {
            let directory = try recordingsDirectory()
            let url = directory.appendingPathComponent("sample-\(UUID().uuidString).wav")
            try recorder.start(url: url)
            recordingURL = url
            startedAt = Date()
            elapsed = 0
            liveLevel = -80
            isRecording = true
            isAnalyzing = false
            errorMessage = nil
            exportMessage = nil
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopRecording() {
        recorder.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        guard elapsed >= 0.6, let url = recordingURL else {
            errorMessage = "Record at least one second so there is enough voice to analyze."
            return
        }
        analyze(url: url)
    }

    private func analyze(url: URL) {
        isAnalyzing = true
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try AudioAnalyzer().analyze(url: url)
                }.value
                session = PracticeSession(audioURL: url, result: result)
            } catch {
                errorMessage = "Analysis failed: \(error.localizedDescription)"
            }
            isAnalyzing = false
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

    private func recordingsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("VoiceCoach/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
