import AppKit
import SwiftUI
import VoiceCoachCore

struct TakeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var plotSelection
    @State private var selectedPlot: AnalysisPlot = .pitch
    @State private var selectedWordIndex: Int?
    @State private var isGraphCopied = false
    @State private var isTranscriptCopied = false

    var body: some View {
        Group {
            if let session = model.selectedSession, let take = model.selectedTake {
                takeWorkspace(session, take: take)
            } else {
                StudioPage(maxWidth: 1050, horizontalPadding: 20) {
                    EmptyState(
                        icon: "waveform",
                        title: "Take not found",
                        detail: "Choose another session from your local library.",
                        actionTitle: "View sessions"
                    ) {
                        model.navigate(to: AppDestination.sessions)
                    }
                }
            }
        }
    }

    private func takeWorkspace(_ session: CoachingSession, take: PracticeSession) -> some View {
        VStack(spacing: 0) {
            StudioScroll {
                VStack(alignment: .leading, spacing: 14) {
                    takeBar(session, take: take)
                    transcriptCard(take)
                    analysisCard(take)
                }
                .id(take.id)
                .transition(.opacity.combined(with: .scale(scale: 0.992, anchor: .top)))
                .animation(takeTransition, value: model.selectedTakeID)
                .frame(maxWidth: 1050, alignment: .topLeading)
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .onChange(of: model.selectedTakeID) { _, _ in
                selectedWordIndex = nil
                isTranscriptCopied = false
            }

            stickyTransport(take)
        }
    }

    private func takeBar(_ session: CoachingSession, take: PracticeSession) -> some View {
        HStack(spacing: 12) {
            WorkspaceChromeButtons(includeBack: true)

            Label(take.takeSource.title, systemImage: take.takeSource.icon)
                .font(.callout.weight(.medium))

            Text("\(take.createdAt.formatted(date: .omitted, time: .shortened)) · \(vcNumber(take.result.metrics.duration, 1))s")
                .font(.caption)
                .foregroundStyle(Studio.secondary)

            Spacer()

            if snapshot {
                Text("Take \(takeNumber(take, in: session)) of \(session.takeCount)")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 6))
            } else {
                Picker("Take", selection: Binding(
                    get: { model.selectedTakeID ?? take.id },
                    set: { takeID in model.selectTake(takeID) }
                )) {
                    ForEach(Array(session.takes.enumerated()), id: \.element.id) { index, item in
                        Text("Take \(index + 1) of \(session.takeCount)").tag(item.id)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
        }
        .frame(minHeight: 32)
    }

    private func transcriptCard(_ take: PracticeSession) -> some View {
        let highlightedWordIndex = highlightedWordIndex(in: take)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SectionEyebrow(text: "Words")
                Spacer()
                if let transcription = take.transcription {
                    Text("\(transcription.words.count) words")
                        .font(.caption)
                        .foregroundStyle(Studio.secondary)
                    copyTranscriptButton(transcription.text)
                }
            }

            if let transcription = take.transcription {
                TakeTranscriptPane(
                    transcription: transcription,
                    highlightedWordIndex: highlightedWordIndex,
                    isPlaying: model.isPlaying,
                    reduceMotion: reduceMotion
                ) { index, word in
                    selectedWordIndex = selectedWordIndex == index ? nil : index
                    model.seek(to: word.start)
                }
            } else {
                ContentUnavailableView(
                    "Transcript Unavailable",
                    systemImage: "text.badge.xmark",
                    description: Text(model.transcriptionNotice ?? "This take has audio and acoustic measurements, but no transcript.")
                )
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
        .studioCard()
    }

    private func copyTranscriptButton(_ text: String) -> some View {
        Button(action: { copyTranscript(text) }) {
            Label(
                isTranscriptCopied ? "Copied" : "Copy Transcript",
                systemImage: isTranscriptCopied ? "checkmark" : "doc.on.doc"
            )
        }
        .buttonStyle(.bordered)
        .help("Copy the full transcript text")
        .disabled(text.isEmpty)
        .task(id: isTranscriptCopied) {
            guard isTranscriptCopied else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { isTranscriptCopied = false }
        }
    }

    private func stickyTransport(_ take: PracticeSession) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Studio.line)
                .frame(height: 1)

            TakePlaybackRow(
                take: take,
                large: true,
                spaceShortcut: true,
                highlightedRange: selectedRange(take)
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 1050)
            .frame(maxWidth: .infinity)
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Studio.surface.opacity(0.72))
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Take timeline")
    }

    private func analysisCard(_ take: PracticeSession) -> some View {
        let highlightedRange = selectedRange(take)
        return VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    SectionEyebrow(text: "Analysis")
                    Spacer()
                    plotPicker
                    copyGraphButton(take)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionEyebrow(text: "Analysis")
                        Spacer()
                        copyGraphButton(take)
                    }
                    plotPicker
                }
            }

            ZStack {
                activePlot(take, highlightedRange: highlightedRange, interactive: true)
                    .id(selectedPlot)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
            .animation(plotAnimation, value: selectedPlot)
            .frame(height: 380)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 460, alignment: .topLeading)
        .studioCard()
    }

    private var plotPicker: some View {
        HStack(spacing: 2) {
            ForEach(AnalysisPlot.allCases) { plot in
                Button {
                    withAnimation(plotAnimation) { selectedPlot = plot }
                } label: {
                    Text(plot.rawValue)
                        .font(.caption.weight(.medium))
                        .frame(width: 86, height: 28)
                        .background {
                            if selectedPlot == plot {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Studio.accent)
                                    .matchedGeometryEffect(id: "plot-selection", in: plotSelection)
                            }
                        }
                        .foregroundStyle(selectedPlot == plot ? Studio.background : Studio.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Studio.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Studio.line))
    }

    private func copyGraphButton(_ take: PracticeSession) -> some View {
        Button(action: { copyAnalysisSnapshot(take) }) {
            Label(isGraphCopied ? "Copied" : "Copy Graph", systemImage: isGraphCopied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.bordered)
        .help("Copy the current graph and waveform as a PNG")
        .task(id: isGraphCopied) {
            guard isGraphCopied else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { isGraphCopied = false }
        }
    }

    @ViewBuilder
    private func activePlot(_ take: PracticeSession, highlightedRange: ClosedRange<Double>?, interactive: Bool) -> some View {
        let result = take.result
        switch selectedPlot {
        case .pitch:
            LabeledLineChart(points: result.pitchContour, color: Studio.accent, range: pitchBounds(result), duration: result.metrics.duration, unit: "Hz", playbackTime: interactive ? model.playbackTime : 0, isPlaying: interactive && model.isPlaying, highlightedRange: highlightedRange, onSeek: interactive ? { model.seek(to: $0, autoplay: true) } : nil, onScrub: interactive ? { model.seek(to: $0) } : nil)
        case .loudness:
            LabeledLineChart(points: result.loudnessContour, color: Studio.accent, range: -60...0, duration: result.metrics.duration, unit: "dBFS", playbackTime: interactive ? model.playbackTime : 0, isPlaying: interactive && model.isPlaying, highlightedRange: highlightedRange, onSeek: interactive ? { model.seek(to: $0, autoplay: true) } : nil, onScrub: interactive ? { model.seek(to: $0) } : nil)
        case .spectrum:
            ZStack {
                SpectrogramView(data: result.spectrogram)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                TimeRangeHighlight(range: highlightedRange, duration: result.metrics.duration)
                if interactive {
                    InteractiveGraphOverlay(duration: result.metrics.duration, playbackTime: model.playbackTime, isPlaying: model.isPlaying, onSeek: { model.seek(to: $0, autoplay: true) }, onScrub: { model.seek(to: $0) })
                }
            }
        }
    }

    private func takeNumber(_ take: PracticeSession, in session: CoachingSession) -> Int {
        (session.takes.firstIndex(where: { $0.id == take.id }) ?? 0) + 1
    }

    private func selectedRange(_ take: PracticeSession) -> ClosedRange<Double>? {
        guard let highlightedWordIndex = highlightedWordIndex(in: take),
              let words = take.transcription?.words,
              words.indices.contains(highlightedWordIndex)
        else { return nil }
        return words[highlightedWordIndex].start...words[highlightedWordIndex].end
    }

    private func highlightedWordIndex(in take: PracticeSession) -> Int? {
        guard let words = take.transcription?.words else { return selectedWordIndex }
        if let active = words.firstIndex(where: { $0.start <= model.playbackTime && model.playbackTime <= $0.end }) {
            return active
        }
        return selectedWordIndex
    }

    private var takeTransition: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    private var plotAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.28, extraBounce: 0)
    }

    private func copyTranscript(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        isTranscriptCopied = true
        model.toastMessage = "Transcript copied"
    }

    @MainActor
    private func copyAnalysisSnapshot(_ take: PracticeSession) {
        let renderer = ImageRenderer(content: analysisClipboardSnapshot(take))
        renderer.scale = 2

        guard let image = renderer.nsImage else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        if let cgImage = renderer.cgImage,
           let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) {
            pasteboard.setData(data, forType: .png)
        }
        isGraphCopied = true
        model.toastMessage = "\(selectedPlot.rawValue) graph copied as PNG"
    }

    private func analysisClipboardSnapshot(_ take: PracticeSession) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("VOICE COACH · \(selectedPlot.rawValue.uppercased()) ANALYSIS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(Studio.secondary)
                Spacer()
                Text("\(vcNumber(take.result.metrics.duration, 1))s")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Studio.secondary)
            }
            activePlot(take, highlightedRange: selectedRange(take), interactive: false)
                .frame(height: 225)
            Divider()
            AlignedWaveformRow(
                points: take.result.waveform,
                duration: take.result.metrics.duration,
                highlightedRange: selectedRange(take)
            )
            .frame(height: 46)
        }
        .padding(24)
        .frame(width: 980)
        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Studio.line))
        .preferredColorScheme(.dark)
        .environment(\.studioSnapshot, true)
    }

    private func pitchBounds(_ result: AnalysisResult) -> ClosedRange<Double> {
        let values = result.pitchContour.map(\.value).filter { $0.isFinite && $0 > 0 }
        let low = floor(((values.min() ?? 100) - 25) / 25) * 25
        let high = ceil(((values.max() ?? 250) + 25) / 25) * 25
        return max(0, low)...max(high, low + 50)
    }
}

enum AnalysisPlot: String, CaseIterable, Identifiable {
    case pitch = "Pitch"
    case loudness = "Loudness"
    case spectrum = "Spectrum"

    var id: Self { self }
}
