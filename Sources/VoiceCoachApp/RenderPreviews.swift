#if DEBUG
import AppKit
import SwiftUI
import VoiceCoachCore

/// Opt-in visual and persistence fixtures; never reads the microphone or personal recordings.
@MainActor
func renderStudioPreviewsIfRequested() {
    guard let index = CommandLine.arguments.firstIndex(of: "--render-previews"),
          CommandLine.arguments.indices.contains(index + 1) else { return }
    let output = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
    let fixtureRoot = output.appendingPathComponent("fixture-library", isDirectory: true)

    do {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fixtureRoot.path) {
            try FileManager.default.removeItem(at: fixtureRoot)
        }
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)

        let sessions = makePreviewSessions(root: fixtureRoot)
        let store = try SessionStore(rootURL: fixtureRoot)

        // Fat schema v1 → thin schema v3 migration
        let legacySessions = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Array(sessions.prefix(3))))
        let legacyData = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "sessions": legacySessions])
        try legacyData.write(to: fixtureRoot.appendingPathComponent("session-library.json"), options: .atomic)
        let migratedSource = try store.load()
        precondition(migratedSource.count == 3, "Version 1 library could not be read")
        precondition(
            FileManager.default.fileExists(atPath: fixtureRoot.appendingPathComponent("session-library-v1-backup.json").path),
            "Migration backup missing"
        )

        try store.save(sessions, analysisTakeIDs: nil)
        try assertThinLibraryLayout(store: store, sessions: sessions)

        let model = AppModel(storageRoot: fixtureRoot)
        precondition(model.sessions == sessions.sorted { $0.updatedAt > $1.updatedAt })
        precondition(model.totalTakeCount == sessions.reduce(0) { $0 + $1.takeCount })

        // Metadata-only save must not rewrite analysis blobs (Mimic style / rename path).
        let probeSession = model.sessions[0]
        let probeTake = probeSession.takes[0]
        let analysisURL = store.analysisURL(sessionID: probeSession.id, takeID: probeTake.id)
        let beforeAnalysis = try Data(contentsOf: analysisURL)
        try store.save(model.sessions, analysisTakeIDs: [])
        let afterAnalysis = try Data(contentsOf: analysisURL)
        precondition(afterAnalysis == beforeAnalysis, "Metadata save rewrote analysis blob")

        func render(_ name: String, width: CGFloat = 1440, height: CGFloat = 920) throws {
            let view = ContentView()
                .environmentObject(model)
                .environment(\.studioSnapshot, true)
                .frame(width: width, height: height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { throw NSError(domain: "VoiceCoachPreview", code: 1) }
            try png.write(to: output.appendingPathComponent(name + ".png"))
        }

        func renderSettings(_ name: String, width: CGFloat = 520, height: CGFloat = 420) throws {
            let view = SettingsView()
                .environmentObject(model)
                .environment(\.studioSnapshot, true)
                .frame(width: width, height: height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { throw NSError(domain: "VoiceCoachPreview", code: 2) }
            try png.write(to: output.appendingPathComponent(name + ".png"))
        }

        func renderCreateSession(_ name: String, mode: PracticeMode = .general, width: CGFloat = 720, height: CGFloat = 760) throws {
            let view = CreateSessionView(initialMode: mode)
                .environmentObject(model)
                .environment(\.studioSnapshot, true)
                .frame(width: width, height: height)
                .background(Studio.background)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { throw NSError(domain: "VoiceCoachPreview", code: 3) }
            try png.write(to: output.appendingPathComponent(name + ".png"))
        }

        model.destination = .studio
        model.selectedSessionID = nil
        try render("01-studio")
        model.destination = .create
        try renderCreateSession("02-create-session")
        model.resumeSession(model.sessions[0].id)
        try render("03-practice")
        if let latest = model.selectedTake {
            model.openTake(sessionID: model.sessions[0].id, takeID: latest.id)
        }
        try render("04-take", height: 1_360)
        model.destination = .sessions
        try render("05-sessions")
        model.destination = .insights
        try render("06-insights")
        model.transcriptionEngine = .system
        model.systemTranscriptionStatus = .ready(localeIdentifier: "en_US")
        try renderSettings("07-settings")
        model.destination = .practice(model.sessions[0].id)
        model.isRecording = true
        model.liveLevel = -17
        model.elapsed = 12.4
        try render("08-recording")
        model.isRecording = false
        if let mimic = model.sessions.first(where: { $0.mode == .mimic }) {
            model.resumeSession(mimic.id)
            model.mimicWorkspaceMode = .practice
            try render("09-mimic-ready")
            if let attempt = mimic.latestTake {
                model.selectTake(attempt.id)
                model.mimicWorkspaceMode = .compare
                try render("10-mimic-compare")
                if let reference = mimic.mimicReference?.take {
                    let view = MimicComparisonView(reference: reference, attempt: attempt,
                        comparison: MimicComparison.compare(reference: reference, attempt: attempt), initialMetric: "Timing")
                        .environmentObject(model)
                        .environment(\.studioSnapshot, true)
                        .padding(24)
                        .frame(width: 1100, height: 640, alignment: .topLeading)
                        .background(Studio.background)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 1
                    guard let image = renderer.cgImage,
                          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                    else { throw NSError(domain: "VoiceCoachPreview", code: 4) }
                    try png.write(to: output.appendingPathComponent("10b-mimic-timing.png"))
                }
                model.mimicWorkspaceMode = .analysis
                try render("10c-mimic-analysis")
            }
            model.mimicWorkspaceMode = .practice
            model.isRecording = true
            model.mimicPhase = .recording
            model.elapsed = 4.2
            try render("11-mimic-recording")
            model.isRecording = false
            model.mimicPhase = .ready
            model.updateMimicStyle(.speakAlong)
            model.isRecording = true
            model.mimicPhase = .recording
            try render("12-mimic-speak-along")
            model.isRecording = false
            model.mimicPhase = .ready
            model.mimicDraft = MimicReferenceDraft(
                id: UUID(), url: fixtureRoot.appendingPathComponent("preview-only.wav"),
                sourceName: "Interview excerpt", duration: 8,
                peaks: (0..<180).map { Float(0.1 + 0.6 * abs(sin(Double($0) / 8))) },
                source: .importedAudio
            )
            try renderCreateSession("13-mimic-setup", mode: .mimic)
            model.mimicDraft = MimicReferenceDraft(
                id: UUID(), url: fixtureRoot.appendingPathComponent("preview-only-long.wav"),
                sourceName: "Long interview", duration: 180,
                peaks: (0..<2_880).map { Float(0.1 + 0.6 * abs(sin(Double($0) / 8))) },
                source: .importedAudio
            )
            try renderCreateSession("14-mimic-long-setup", mode: .mimic)
        }

        // Hang regression: a multi-thousand-word transcript must layout quickly.
        // Snapshot mode caps the word grid; live mode scrolls the full set.
        let longWords = (0..<3_000).map { index in
            TranscriptWord(word: "w\(index)", start: Double(index) * 0.1, end: Double(index) * 0.1 + 0.08)
        }
        let longTranscription = TranscriptionResult(
            text: longWords.map(\.word).joined(separator: " "),
            words: longWords
        )
        for snapshot in [true, false] {
            let started = ContinuousClock.now
            let pane = TakeTranscriptPane(
                transcription: longTranscription,
                highlightedWordIndex: 12,
                isPlaying: false,
                reduceMotion: true,
                onSelectWord: { _, _ in }
            )
            .environment(\.studioSnapshot, snapshot)
            .frame(width: 540, height: 280)
            let renderer = ImageRenderer(content: pane)
            renderer.scale = 1
            precondition(renderer.cgImage != nil, "Long transcript pane failed to render (snapshot=\(snapshot))")
            let elapsed = started.duration(to: .now)
            precondition(elapsed < .seconds(5), "Long transcript pane hung (snapshot=\(snapshot)): \(elapsed)")
            print("Long transcript pane (snapshot=\(snapshot)): \(elapsed)")
        }

        print("Rendered 15 app previews; v1 migration backup and v2 persistence round-trip passed. Output: \(output.path)")
        exit(0)
    } catch {
        print("Preview rendering failed: \(error)")
        exit(1)
    }
}

/// Starts the offscreen renderer once SwiftUI has created a scene. This keeps
/// command-line preview generation reliable without affecting the shipped app.
struct PreviewRenderLauncher: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { renderStudioPreviewsIfRequested() }
            .accessibilityHidden(true)
    }
}

private func assertThinLibraryLayout(store: SessionStore, sessions: [CoachingSession]) throws {
    let libraryURL = store.rootURL.appendingPathComponent("session-library.json")
    let data = try Data(contentsOf: libraryURL)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    precondition(json?["schemaVersion"] as? Int == SessionStore.currentSchemaVersion, "Expected thin schema v3")
    let text = String(decoding: data, as: UTF8.self)
    precondition(!text.contains("acousticFrames"), "Index must not embed acousticFrames")
    precondition(!text.contains("spectrogram"), "Index must not embed spectrogram")
    precondition(!text.contains("loudnessContour"), "Index must not embed loudnessContour")
    precondition(data.count < 200_000, "Thin index unexpectedly large (\(data.count) bytes)")

    for session in sessions {
        for take in session.takes {
            let url = store.analysisURL(sessionID: session.id, takeID: take.id)
            precondition(FileManager.default.fileExists(atPath: url.path), "Missing analysis for take \(take.id)")
        }
        if let reference = session.mimicReference?.take {
            let url = store.analysisURL(sessionID: session.id, takeID: reference.id)
            precondition(FileManager.default.fileExists(atPath: url.path), "Missing analysis for reference \(reference.id)")
        }
    }

    let reloaded = try store.load()
    precondition(reloaded == sessions.sorted { $0.updatedAt > $1.updatedAt }, "Thin library round-trip mismatch")
}

private func makePreviewSessions(root: URL) -> [CoachingSession] {
    let calendar = Calendar.current
    let now = Date()
    let firstID = UUID()
    let secondID = UUID()
    let thirdID = UUID()
    let mimicID = UUID()

    func take(
        sessionID: UUID,
        frequency: Double,
        duration: Double,
        text: String,
        offsetHours: Int,
        source: TakeSource = .recorded,
        shortPauses: Bool = false,
        takeID: UUID = UUID(),
        audioFileName: String? = nil
    ) -> PracticeSession {
        let rate = 16_000.0
        let samples = (0..<Int(rate * duration)).map { index -> Float in
            let time = Double(index) / rate
        let phrase = time.truncatingRemainder(dividingBy: shortPauses ? 1.1 : 3.1)
        let pauseStart = shortPauses ? 0.75 : 2.66
        let amplitude = phrase > pauseStart ? 0.0002 : (0.18 + 0.07 * sin(time * 2.5))
            let phase = 2 * Double.pi * frequency * time + 4.5 * sin(time * 1.8)
            return Float(amplitude * (sin(phase) + 0.26 * sin(2 * phase)))
        }
        let result = AudioAnalyzer().analyze(samples: samples, sampleRate: rate)
        let tokens = text.split(separator: " ")
        let usable = max(duration - 0.4, 0.1)
        let wordDuration = usable / Double(max(tokens.count, 1))
        let transcriptWords = tokens.enumerated().map { index, token in
            TranscriptWord(
                word: String(token),
                start: 0.2 + Double(index) * wordDuration,
                end: min(duration, 0.2 + Double(index + 1) * wordDuration - 0.03)
            )
        }
        let transcription = TranscriptionResult(text: text, words: transcriptWords)
        let date = calendar.date(byAdding: .hour, value: offsetHours, to: now) ?? now
        let fileName = audioFileName ?? "take-\(takeID.uuidString).wav"
        let audioURL = root
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
            .appendingPathComponent(fileName)
        return PracticeSession(
            id: takeID,
            createdAt: date,
            audioURL: audioURL,
            source: source,
            result: result,
            transcription: transcription,
            words: WordAcousticAnalyzer().analyze(transcription: transcription, result: result)
        )
    }

    let interviewTakes = [
        take(sessionID: firstID, frequency: 145, duration: 10.8, text: "I want to explain my experience clearly and give each idea enough space to land.", offsetHours: -4),
        take(sessionID: firstID, frequency: 154, duration: 11.3, text: "I can connect my experience to the problem and show the result with a calm steady pace.", offsetHours: -3),
        take(sessionID: firstID, frequency: 166, duration: 12.4, text: "I want to speak with a little more inflection and let the most important point be heard.", offsetHours: -2, source: .importedVideo)
    ]
    let first = CoachingSession(
        id: firstID,
        name: "Job Interview Prep",
        createdAt: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
        updatedAt: calendar.date(byAdding: .hour, value: -2, to: now) ?? now,
        mode: .general,
        prompt: "Tell me about a difficult problem you solved and what changed because of your work.",
        keepsRecordings: true,
        takes: interviewTakes
    )
    let secondTake = take(sessionID: secondID, frequency: 174, duration: 9.8, text: "Today I will make the recommendation simple direct and easy to remember.", offsetHours: -24)
    let second = CoachingSession(
        id: secondID,
        name: "Product Presentation",
        createdAt: calendar.date(byAdding: .day, value: -5, to: now) ?? now,
        updatedAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
        mode: .freeSpeaking,
        prompt: "Explain the product decision in thirty seconds.",
        keepsRecordings: true,
        takes: [secondTake]
    )
    let third = CoachingSession(
        id: thirdID,
        name: "Thoughtful Communication",
        createdAt: calendar.date(byAdding: .day, value: -8, to: now) ?? now,
        updatedAt: calendar.date(byAdding: .day, value: -4, to: now) ?? now,
        mode: .prompt,
        prompt: "A thoughtful pause gives an idea room to land.",
        keepsRecordings: true,
        takes: [take(sessionID: thirdID, frequency: 158, duration: 8.6, text: "A thoughtful pause gives the next idea room to land clearly.", offsetHours: -96)]
    )
    let script = "I really don't think that's a good idea."
    let reference = take(
        sessionID: mimicID,
        frequency: 172,
        duration: 8.0,
        text: script,
        offsetHours: -8,
        source: .importedAudio,
        shortPauses: true,
        audioFileName: "reference.wav"
    )
    let attempt = take(sessionID: mimicID, frequency: 161, duration: 8.7, text: script, offsetHours: -7, shortPauses: true)
    let mimic = CoachingSession(
        id: mimicID,
        name: "A confident answer",
        createdAt: calendar.date(byAdding: .day, value: -6, to: now) ?? now,
        updatedAt: calendar.date(byAdding: .day, value: -6, to: now) ?? now,
        mode: .mimic, prompt: "", keepsRecordings: true,
        takes: [attempt],
        mimicReference: MimicReference(sourceName: "Interview excerpt", take: reference, sourceStart: 0, sourceEnd: 8),
        mimicStyle: .listenAndRepeat
    )
    return [first, second, third, mimic]
}
#endif
