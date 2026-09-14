#if DEBUG
import AppKit
import SwiftUI
import VoiceCoachCore

/// Opt-in visual fixtures; never reads the microphone or personal recordings.
@MainActor
func renderStudioPreviewsIfRequested() {
    guard let index = CommandLine.arguments.firstIndex(of: "--render-previews"),
          CommandLine.arguments.indices.contains(index + 1) else { return }
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel()
        func render(_ name: String, width: CGFloat = 1120, height: CGFloat = 840, plot: AnalysisPlot = .pitch, expanded: Bool = false) throws {
            let view = ContentView(initialPlot: plot, reportExpanded: expanded).environmentObject(model)
                .environment(\.studioSnapshot, true)
                .frame(width: width, height: height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw NSError(domain: "StudioPreview", code: 1)
            }
            try png.write(to: directory.appendingPathComponent(name + ".png"))
        }
        try render("studio-ready")
        try render("studio-compact", width: 800, height: 680)
        model.isRecording = true
        model.liveLevel = -18
        model.elapsed = 12.4
        try render("studio-recording")
        model.isRecording = false
        model.isAnalyzing = true
        try render("studio-analyzing")
        model.isAnalyzing = false
        let rate = 16_000.0
        let samples = (0..<Int(rate * 12)).map { index -> Float in
            let time = Double(index) / rate
            let phrase = time.truncatingRemainder(dividingBy: 3)
            let amplitude = phrase > 2.5 ? 0.0001 : (0.18 + 0.1 * sin(time * 3))
            let phase = 2 * Double.pi * 168 * time + 4 * sin(time * 2)
            return Float(amplitude * (sin(phase) + 0.3 * sin(2 * phase)))
        }
        let result = AudioAnalyzer().analyze(samples: samples, sampleRate: rate)
        model.session = PracticeSession(audioURL: directory.appendingPathComponent("synthetic.wav"), result: result)
        try render("studio-results", height: 1160)
        try render("studio-results-compact", width: 800, height: 1160)
        try render("studio-wide", width: 1600, height: 1160)
        try render("studio-loudness", height: 1160, plot: .loudness)
        try render("studio-spectrum", height: 1160, plot: .spectrum)
        try render("studio-report", height: 1480, expanded: true)

        // These transitions must not request the microphone or replace the previous take.
        let previous = model.session
        model.isAnalyzing = true
        model.recordButtonPressed()
        precondition(!model.isRecording && model.session == previous)
        model.isAnalyzing = false
        model.isRequestingPermission = true
        model.recordButtonPressed()
        precondition(!model.isRecording && model.session == previous)
        model.isRequestingPermission = false
        let silence = AudioAnalyzer().analyze(samples: [Float](repeating: 0, count: 16000), sampleRate: rate)
        model.session = PracticeSession(audioURL: directory.appendingPathComponent("silence.wav"), result: silence)
        try render("studio-silence", height: 1160)
        print("Rendered 11 SwiftUI layout previews; busy-state guards passed. Output: \(directory.path)")
        exit(0)
    } catch {
        print("Preview rendering failed: \(error)")
        exit(1)
    }
}
#endif
