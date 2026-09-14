import SwiftUI
import VoiceCoachCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPlot: AnalysisPlot = .pitch
    @State private var showReport = false
    @State private var showPractice = true

    init(initialPlot: AnalysisPlot = .pitch, reportExpanded: Bool = false) {
        _selectedPlot = State(initialValue: initialPlot)
        _showReport = State(initialValue: reportExpanded)
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 1000
            ZStack {
                Studio.background.ignoresSafeArea()
                RadialGradient(colors: [Studio.accent.opacity(0.045), .clear], center: .topTrailing, startRadius: 0, endRadius: 650)
                    .ignoresSafeArea().allowsHitTesting(false)
                VStack(spacing: 0) {
                    header.padding(.horizontal, compact ? 28 : 42).padding(.top, 24).padding(.bottom, 22)
                    Rectangle().fill(Studio.line).frame(height: 1)
                    StudioScroll {
                        VStack(alignment: .leading, spacing: 0) {
                            recordingStage(compact: compact)
                            if let session = model.session, !model.isRecording, !model.isAnalyzing {
                                results(session)
                            } else if !model.isRecording && !model.isAnalyzing {
                                practiceGuide
                            }
                            footer.padding(.top, 28).padding(.bottom, 24)
                        }
                        .frame(maxWidth: 1200)
                        .padding(.horizontal, compact ? 32 : 54)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .foregroundStyle(Studio.ink)
        .preferredColorScheme(.dark)
        .tint(Studio.accent)
        .alert("Voice Coach", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .overlay(alignment: .bottom) {
            if let message = model.exportMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(Studio.ink)
                    .padding(.horizontal, 20).padding(.vertical, 13)
                    .background(Studio.surface, in: Capsule())
                    .overlay(Capsule().stroke(Studio.line))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
                    .padding(.bottom, 22)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.5))
                        if !Task.isCancelled, model.exportMessage == message { model.exportMessage = nil }
                    }
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform").font(.system(size: 22, weight: .medium)).foregroundStyle(Studio.accent)
            Text("Voice Coach").font(.system(size: 18, weight: .semibold)).tracking(-0.5)
            Text("STUDIO / 02").font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.2).foregroundStyle(Studio.secondary).padding(.leading, 12)
            Spacer()
            Label("On-device · Private", systemImage: "lock")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Studio.secondary)
                .help("Recordings and analysis stay on this Mac. Nothing is uploaded.")
        }
    }

    private func recordingStage(compact: Bool) -> some View {
        let hasResult = model.session != nil && !model.isRecording && !model.isAnalyzing
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: hasResult ? 16 : 23) {
                HStack(spacing: 8) {
                    Circle().fill(model.isRecording ? Color.orange : Studio.accent).frame(width: 5, height: 5)
                    SectionEyebrow(text: model.isRecording ? "Recording in progress" : model.isAnalyzing ? "Processing on your Mac" : hasResult ? "Keep finding your voice" : "Your personal voice studio")
                }
                Text(model.isRecording ? "Make yourself\nheard." : model.isAnalyzing ? "A moment\nof reflection." : hasResult ? "One take.\nA little more clarity." : "A little practice.\nA voice that’s you.")
                    .font(.system(size: hasResult ? 34 : compact ? 43 : 52, weight: .regular))
                    .tracking(-1.8).lineSpacing(-3).fixedSize(horizontal: false, vertical: true)
                Text(stageDescription)
                    .font(.system(size: 13)).foregroundStyle(Studio.secondary)
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 390, alignment: .leading)
                HStack(spacing: 16) {
                    Button(action: model.recordButtonPressed) {
                        Label(model.isRecording ? "Finish recording" : model.isAnalyzing ? "Analyzing…" : hasResult ? "Record again" : "Start recording",
                              systemImage: model.isRecording ? "stop.fill" : "mic.fill")
                    }
                    .buttonStyle(StudioButtonStyle(prominent: true, destructive: model.isRecording))
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(model.isAnalyzing || model.isRequestingPermission)
                    .accessibilityHint("Record a short voice sample. Press Space again to finish.")
                    if model.isAnalyzing || model.isRequestingPermission {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(model.isRecording ? duration(model.elapsed) : "SPACE")
                            .font(.system(size: model.isRecording ? 18 : 9, weight: .medium, design: .monospaced))
                            .tracking(model.isRecording ? 0 : 1).monospacedDigit().foregroundStyle(Studio.secondary)
                    }
                }
                if model.isRecording {
                    VStack(alignment: .leading, spacing: 8) {
                        LiveMeterView(level: model.liveLevel)
                        Text("MIC LEVEL   ·   \(Int(model.liveLevel)) dBFS   ·   90s maximum")
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(Studio.secondary)
                    }.frame(maxWidth: 320)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VoiceSculpture(recording: model.isRecording, level: model.liveLevel)
                .frame(width: compact ? 260 : 360, height: hasResult ? 250 : 340)
                .overlay(alignment: .bottom) {
                    if !hasResult {
                        Text(model.isRecording ? "LISTENING TO YOU" : "ROOM FOR YOUR VOICE")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .tracking(2.5).foregroundStyle(Studio.secondary.opacity(0.8))
                            .padding(.bottom, 5)
                    }
                }
        }
        .padding(.vertical, hasResult ? 22 : 32)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.isRecording)
    }

    private var stageDescription: String {
        if model.isRecording { return "Speak naturally. Leave a little space between thoughts.\nFinish when you’re ready." }
        if model.isAnalyzing { return "Measuring pitch, loudness, pauses and voice quality.\nYour results will appear here." }
        if model.session != nil { return "Listen back. Notice one thing. Try it a little differently." }
        return "Take 10–30 seconds to speak, listen and discover.\nSmall adjustments start with hearing yourself." 
    }

    private var practiceGuide: some View {
        VStack(alignment: .leading, spacing: 20) {
            Rectangle().fill(Studio.line).frame(height: 1)
            HStack {
                SectionEyebrow(text: "A place to begin")
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showPractice.toggle() }
                } label: {
                    Label(showPractice ? "Hide prompt" : "Show prompt", systemImage: showPractice ? "minus" : "plus")
                }.buttonStyle(StudioButtonStyle())
            }
            if showPractice {
                HStack(alignment: .top, spacing: 28) {
                    Text("“").font(.system(size: 58, weight: .light, design: .serif)).foregroundStyle(Studio.accent)
                    VStack(alignment: .leading, spacing: 15) {
                        Text("I want to speak with a little more intention. To take my time, finish my thoughts, and let my voice be heard.")
                            .font(.system(size: 22, weight: .regular, design: .serif)).lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 650, alignment: .leading)
                        Text("Read this aloud, or simply tell us about your day.")
                            .font(.system(size: 11)).foregroundStyle(Studio.secondary)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 26) {
                    practiceTip("01", "Find a quiet spot")
                    practiceTip("02", "Keep the mic distance steady")
                    practiceTip("03", "Speak in your usual voice")
                }.padding(.top, 7)
            }
        }
        .padding(.top, 8)
    }

    private func practiceTip(_ number: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(number).font(.system(size: 9, design: .monospaced)).foregroundStyle(Studio.accent)
            Text(text).font(.system(size: 11)).foregroundStyle(Studio.secondary)
        }
    }

    private func results(_ session: PracticeSession) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Rectangle().fill(Studio.line).frame(height: 1)
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    SectionEyebrow(text: "The latest take")
                    HStack(spacing: 8) {
                        Text("Your voice, in focus.").font(.system(size: 23)).tracking(-0.6)
                        Text("\(number(session.result.metrics.duration, 1))s · \(session.createdAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Studio.secondary)
                    }
                }
                Spacer()
                Button(action: model.playCurrent) {
                    Label(model.isPlaying ? "Stop" : "Listen", systemImage: model.isPlaying ? "stop.fill" : "play.fill")
                }.buttonStyle(StudioButtonStyle())
                Button(action: model.exportCurrent) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(StudioButtonStyle()).accessibilityLabel("Export recording and report")
                    .help("Export recording.wav and voice-report.json")
            }
            metricGrid(session.result.metrics)
            plots(session.result)
            reportPanel
        }
    }

    private func metricGrid(_ metrics: VoiceMetrics) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), alignment: .leading, spacing: 24) {
            MetricReadout(title: "Median pitch", value: optional(metrics.medianPitchHz, 0), unit: "Hz", detail: pitchRange(metrics))
            MetricReadout(title: "Pitch range", value: optional(metrics.pitchRangeSemitones, 1), unit: "st", detail: "5th–95th percentile")
            MetricReadout(title: "Mean loudness", value: number(metrics.meanLoudnessDBFS, 1), unit: "dBFS", detail: "During active speech")
            MetricReadout(title: "Phrase ending", value: signed(metrics.phraseDecayDB), unit: "dB", detail: "End relative to start")
            MetricReadout(title: "Signal to noise", value: number(metrics.snrDB, 1), unit: "dB", detail: "Recording quality", secondary: true)
            MetricReadout(title: "HNR estimate", value: optional(metrics.hnrDB, 1), unit: "dB", detail: "Periodicity proxy", secondary: true)
            MetricReadout(title: "CPP estimate", value: optional(metrics.cppDB, 1), unit: "dB", detail: "Cepstral prominence", secondary: true)
            MetricReadout(title: "Pauses", value: "\(metrics.pauseCount)", unit: "", detail: "\(number(metrics.pauseRatio * 100, 0))% of recording", secondary: true)
        }
        .padding(.vertical, 8)
    }

    private func plots(_ result: AnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionEyebrow(text: "Listen closer")
                Spacer()
                HStack(spacing: 2) {
                    ForEach(AnalysisPlot.allCases) { plot in
                        Button { selectedPlot = plot } label: {
                            Text(plot.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(selectedPlot == plot ? Studio.ink : Studio.secondary)
                                .frame(width: 82, height: 28)
                                .background(selectedPlot == plot ? Studio.accent.opacity(0.15) : .clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(plot.rawValue) chart")
                        .accessibilityAddTraits(selectedPlot == plot ? [.isSelected] : [])
                    }
                }.padding(4).modifier(ControlGlass(tint: nil, opaque: false))
            }
            Group {
                switch selectedPlot {
                case .pitch:
                    LabeledLineChart(
                        points: result.pitchContour,
                        color: Studio.accent,
                        range: pitchBounds(result),
                        duration: result.metrics.duration,
                        unit: "Hz",
                        playbackTime: model.playbackTime,
                        isPlaying: model.isPlaying,
                        onSeek: { time in model.seek(to: time, autoplay: true) },
                        onScrub: { time in model.seek(to: time, autoplay: false) }
                    )
                case .loudness:
                    LabeledLineChart(
                        points: result.loudnessContour,
                        color: Studio.accent,
                        range: -60...0,
                        duration: result.metrics.duration,
                        unit: "dBFS",
                        playbackTime: model.playbackTime,
                        isPlaying: model.isPlaying,
                        onSeek: { time in model.seek(to: time, autoplay: true) },
                        onScrub: { time in model.seek(to: time, autoplay: false) }
                    )
                case .spectrum:
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            VStack(alignment: .trailing) {
                                Text("\(Int(min(8000, result.metrics.sampleRateHz / 2))) Hz")
                                Spacer()
                                Text("\(Int(min(4000, result.metrics.sampleRateHz / 4))) Hz")
                                Spacer()
                                Text("0 Hz")
                            }
                            .frame(width: 55, alignment: .trailing)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Studio.secondary)

                            ZStack {
                                SpectrogramView(data: result.spectrogram)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                InteractiveGraphOverlay(
                                    duration: result.metrics.duration,
                                    playbackTime: model.playbackTime,
                                    isPlaying: model.isPlaying,
                                    points: nil,
                                    unit: nil,
                                    onSeek: { time in model.seek(to: time, autoplay: true) },
                                    onScrub: { time in model.seek(to: time, autoplay: false) }
                                )
                            }
                        }
                        HStack {
                            Text("0s")
                            Spacer()
                            Text(String(format: "%.1fs", result.metrics.duration / 2))
                            Spacer()
                            Text(String(format: "%.1fs", result.metrics.duration))
                        }
                        .padding(.leading, 67)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Studio.secondary)
                    }
                }
            }.frame(height: 164)
            Rectangle().fill(Studio.line).frame(height: 1)
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "waveform").font(.system(size: 13, weight: .medium))
                    if model.isPlaying || model.playbackTime > 0.05 {
                        Text(String(format: "%.1fs", model.playbackTime))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Studio.accent)
                    } else {
                        Text(String(format: "%.1fs", result.metrics.duration))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Studio.secondary)
                    }
                }
                .frame(width: 55, alignment: .trailing)
                .foregroundStyle(Studio.secondary)

                InteractiveWaveformView(
                    points: result.waveform,
                    duration: result.metrics.duration,
                    playbackTime: model.playbackTime,
                    isPlaying: model.isPlaying,
                    color: Studio.accent,
                    onSeek: { time in model.seek(to: time, autoplay: true) },
                    onScrub: { time in model.seek(to: time, autoplay: false) }
                )
                .frame(height: 38)
            }
        }
        .padding(22)
        .background(Studio.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Studio.line))
    }

    private var reportPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Button { showReport.toggle() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right").rotationEffect(.degrees(showReport ? 90 : 0))
                            .font(.system(size: 9, weight: .semibold))
                        Text("Structured voice data").font(.system(size: 12, weight: .medium))
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityValue(showReport ? "Expanded" : "Collapsed")
                Text("Ready for your AI coach").font(.system(size: 11)).foregroundStyle(Studio.secondary)
                Spacer()
                Button(action: model.copyReport) { Label("Copy JSON", systemImage: "doc.on.doc") }
                    .buttonStyle(StudioButtonStyle())
            }
            if showReport {
                StudioScroll {
                    Text(model.report).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(18)
                }.frame(height: 280)
                    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Six-section acoustic analysis report")
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield").foregroundStyle(Studio.accent)
            Text("Only on your Mac. Coaching measurements, not a medical assessment.\nUse the same microphone setup when comparing takes.")
                .lineSpacing(3)
            Spacer()
            Text("SPEAK. LISTEN. GROW.").font(.system(size: 8, design: .monospaced)).tracking(1.5)
        }.font(.system(size: 10)).foregroundStyle(Studio.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
    private func duration(_ seconds: TimeInterval) -> String {
        String(format: "%02d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
    private func playbackDurationLabel(current: Double, total: Double) -> String {
        if model.isPlaying || current > 0.05 {
            return "\(number(current, 1))s / \(number(total, 1))s"
        } else {
            return "\(number(total, 1))s"
        }
    }
    private func number(_ value: Double, _ decimals: Int) -> String { value.formatted(.number.precision(.fractionLength(decimals))) }
    private func optional(_ value: Double?, _ decimals: Int) -> String { value.map { number($0, decimals) } ?? "—" }
    private func signed(_ value: Double) -> String { (value >= 0 ? "+" : "") + number(value, 1) }
    private func pitchRange(_ metrics: VoiceMetrics) -> String {
        guard let low = metrics.pitchLowHz, let high = metrics.pitchHighHz else { return "Not enough voiced audio" }
        return "\(number(low, 0))–\(number(high, 0)) Hz range"
    }
    private func pitchBounds(_ result: AnalysisResult) -> ClosedRange<Double> {
        let values = result.pitchContour.map(\.value).filter { $0.isFinite && $0 > 0 }
        let low = floor(((values.min() ?? 100) - 25) / 25) * 25
        let high = ceil(((values.max() ?? 250) + 25) / 25) * 25
        return max(0, low)...max(high, low + 50)
    }
}

enum AnalysisPlot: String, CaseIterable, Identifiable {
    case pitch = "Pitch", loudness = "Loudness", spectrum = "Spectrum"
    var id: Self { self }
}

private struct MetricReadout: View {
    let title: String
    let value: String
    let unit: String
    let detail: String
    var secondary = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 11)).foregroundStyle(Studio.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(.system(size: secondary ? 25 : 34, weight: .regular)).tracking(-1).monospacedDigit()
                    .foregroundStyle(secondary ? Studio.ink : Studio.accent)
                Text(unit).font(.system(size: 11)).foregroundStyle(Studio.secondary)
            }
            Text(detail).font(.system(size: 10)).foregroundStyle(Studio.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}
