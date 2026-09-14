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
        let iconset = directory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let renderer = ImageRenderer(content: StudioIconArtwork().frame(width: 1024, height: 1024))
                renderer.scale = Double(size * scale) / 1024
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "StudioIcon", code: 1)
                }
                let suffix = scale == 2 ? "@2x" : ""
                try png.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
            }
        }
        print("Rendered 11 SwiftUI layout previews; busy-state guards passed. Output: \(directory.path)")
        exit(0)
    } catch {
        print("Preview rendering failed: \(error)")
        exit(1)
    }
}

private struct StudioIconArtwork: View {
    private let heights: [CGFloat] = [150, 310, 460, 310, 150]
    var body: some View {
        ZStack {
            // Keep the icon fully opaque so iconutil accepts every representation.
            Studio.background
            RoundedRectangle(cornerRadius: 190, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.24, blue: 0.23), Studio.background],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 190, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Studio.accent.opacity(0.65), .white.opacity(0.03), Studio.accent.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
            Circle().fill(Studio.accent.opacity(0.09)).blur(radius: 50).padding(90)
            HStack(spacing: 35) {
                ForEach(0..<heights.count, id: \.self) { index in
                    Capsule().fill(LinearGradient(colors: [Color(red: 0.85, green: 1, blue: 0.9), Studio.accent, Color(red: 0.36, green: 0.62, blue: 0.53)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: heights[index])
                        .shadow(color: Studio.accent.opacity(0.2), radius: 15, y: 6)
                }
            }
        }
        .padding(100)
    }
}
#endif
