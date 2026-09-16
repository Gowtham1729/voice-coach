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
        let sessions = makePreviewSessions(root: fixtureRoot)
        let store = try SessionStore(rootURL: fixtureRoot)
        try store.save(sessions)

        let model = AppModel(storageRoot: fixtureRoot)
        precondition(model.sessions == sessions.sorted { $0.updatedAt > $1.updatedAt })
        precondition(model.totalTakeCount == sessions.reduce(0) { $0 + $1.takeCount })

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

        func renderSettings(_ name: String, width: CGFloat = 620, height: CGFloat = 720) throws {
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

        func renderCreateSession(_ name: String, width: CGFloat = 720, height: CGFloat = 760) throws {
            let view = CreateSessionView()
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

        print("Rendered 8 major-upgrade previews; persistence round-trip passed. Output: \(output.path)")
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

private func makePreviewSessions(root: URL) -> [CoachingSession] {
    let calendar = Calendar.current
    let now = Date()

    func take(
        frequency: Double,
        duration: Double,
        text: String,
        offsetHours: Int,
        source: TakeSource = .recorded
    ) -> PracticeSession {
        let rate = 16_000.0
        let samples = (0..<Int(rate * duration)).map { index -> Float in
            let time = Double(index) / rate
            let phrase = time.truncatingRemainder(dividingBy: 3.1)
            let amplitude = phrase > 2.66 ? 0.0002 : (0.18 + 0.07 * sin(time * 2.5))
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
        return PracticeSession(
            createdAt: date,
            audioURL: root.appendingPathComponent(UUID().uuidString + ".wav"),
            source: source,
            result: result,
            transcription: transcription,
            words: WordAcousticAnalyzer().analyze(transcription: transcription, result: result)
        )
    }

    let interviewTakes = [
        take(frequency: 145, duration: 10.8, text: "I want to explain my experience clearly and give each idea enough space to land.", offsetHours: -4),
        take(frequency: 154, duration: 11.3, text: "I can connect my experience to the problem and show the result with a calm steady pace.", offsetHours: -3),
        take(frequency: 166, duration: 12.4, text: "I want to speak with a little more inflection and let the most important point be heard.", offsetHours: -2, source: .importedVideo)
    ]
    let first = CoachingSession(
        name: "Job Interview Prep",
        createdAt: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
        updatedAt: calendar.date(byAdding: .hour, value: -2, to: now) ?? now,
        mode: .general,
        prompt: "Tell me about a difficult problem you solved and what changed because of your work.",
        keepsRecordings: true,
        takes: interviewTakes
    )
    let secondTake = take(frequency: 174, duration: 9.8, text: "Today I will make the recommendation simple direct and easy to remember.", offsetHours: -24)
    let second = CoachingSession(
        name: "Product Presentation",
        createdAt: calendar.date(byAdding: .day, value: -5, to: now) ?? now,
        updatedAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
        mode: .freeSpeaking,
        prompt: "Explain the product decision in thirty seconds.",
        keepsRecordings: true,
        takes: [secondTake]
    )
    let third = CoachingSession(
        name: "Thoughtful Communication",
        createdAt: calendar.date(byAdding: .day, value: -8, to: now) ?? now,
        updatedAt: calendar.date(byAdding: .day, value: -4, to: now) ?? now,
        mode: .prompt,
        prompt: "A thoughtful pause gives an idea room to land.",
        keepsRecordings: true,
        takes: [take(frequency: 158, duration: 8.6, text: "A thoughtful pause gives the next idea room to land clearly.", offsetHours: -96)]
    )
    return [first, second, third]
}
#endif
