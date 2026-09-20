import AppKit
import SwiftUI
import VoiceCoachCore

struct TakeView: View {
    /// When true, Mimic owns take selection chrome; this view supplies content + transport only.
    var embedded = false

    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPlot: AnalysisPlot = .pitch
    @State private var selectedWordIndex: Int?
    @State private var isGraphCopied = false
    @State private var isTranscriptCopied = false
    @State private var isHandlingWordStep = false

    var body: some View {
        Group {
            if let session = model.selectedSession, let take = model.selectedTake {
                takeWorkspace(session, take: take)
            } else {
                StudioPage(maxWidth: 1050, horizontalPadding: 20) {
                    EmptyState(
                        icon: "waveform",
                        title: "Recording not found",
                        detail: "Choose another recording from your local library.",
                        actionTitle: "View library"
                    ) {
                        model.navigate(to: .library)
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
                .animation(quickMotion, value: model.selectedTakeID)
                .frame(maxWidth: 1050, alignment: .topLeading)
                .padding(.horizontal, 20)
                .padding(.top, embedded ? 8 : 28)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .onChange(of: model.selectedTakeID) { _, _ in
                selectedWordIndex = nil
                isTranscriptCopied = false
            }
            .onChange(of: model.isPlaying) { _, playing in
                // Manual selection only anchors seek; once playback runs, follow the timeline.
                if playing { selectedWordIndex = nil }
            }

            stickyTransport(take)
        }
        .background(wordStepShortcuts(for: take))
    }

    private func takeBar(_ session: CoachingSession, take: PracticeSession) -> some View {
        HStack(spacing: 12) {
            Label(take.takeSource.title, systemImage: take.takeSource.icon)
                .font(.callout.weight(.medium))

            Text("\(take.createdAt.formatted(date: .omitted, time: .shortened)) · \(vcNumber(take.result.metrics.duration, 1))s")
                .font(.caption)
                .foregroundStyle(Studio.secondary)

            Spacer()

            if embedded {
                Text("Take \(takeNumber(take, in: session)) of \(session.takeCount)")
                    .font(.caption)
                    .foregroundStyle(Studio.secondary)
            } else if snapshot {
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

            if !embedded, !session.isMimic {
                if !snapshot, model.isRecording {
                    LiveMeterView(level: model.liveLevel)
                        .frame(width: 120)
                    Text(vcDuration(model.elapsed))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.red)
                        .frame(width: 56, alignment: .trailing)
                    Button("Stop", action: model.recordButtonPressed)
                        .tint(.red)
                        .studioGlassButton(prominent: true)
                        .disabled(model.isAnalyzing || model.isRequestingPermission)
                        .accessibilityLabel("Stop recording")
                } else {
                    Button("Record another", action: model.recordButtonPressed)
                        .studioGlassButton(prominent: true)
                        .disabled(model.isRecording || model.isAnalyzing || model.isRequestingPermission)
                }
            }
            if !embedded, take.takeSource != .recorded {
                Button("Use as Mimic") { model.useCurrentRecordingAsMimicReference() }
                    .tint(.primary)
                    .studioGlassButton()
                    .disabled(model.isRecording || model.isAnalyzing)
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
        StudioQuietIconButton(
            systemImage: "doc.on.doc",
            help: isTranscriptCopied ? "Copied" : "Copy transcript",
            confirmed: isTranscriptCopied
        ) {
            copyTranscript(text)
        }
        .disabled(text.isEmpty)
        .task(id: isTranscriptCopied) {
            await clearCopiedFlag(isTranscriptCopied) { isTranscriptCopied = false }
        }
    }

    private func stickyTransport(_ take: PracticeSession) -> some View {
        let hasWords = !(take.transcription?.words.isEmpty ?? true)
        return VStack(spacing: 0) {
            Rectangle()
                .fill(Studio.line)
                .frame(height: 1)

            TakePlaybackRow(
                take: take,
                large: true,
                spaceShortcut: true,
                highlightedRange: selectedRange(take),
                canStepPreviousWord: canStepWord(in: take, by: -1),
                canStepNextWord: canStepWord(in: take, by: 1),
                onPreviousWord: hasWords ? { stepWord(in: take, by: -1) } : nil,
                onNextWord: hasWords ? { stepWord(in: take, by: 1) } : nil,
                onSeek: { time in
                    selectedWordIndex = nil
                    model.seek(to: time, autoplay: true)
                },
                onScrub: { time in
                    selectedWordIndex = nil
                    model.seek(to: time)
                }
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 1050)
            .frame(maxWidth: .infinity)
        }
        .background {
            if snapshot {
                Studio.surface
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Studio.surface.opacity(0.72))
                    .ignoresSafeArea(edges: .bottom)
            }
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
                    .transition(.opacity)
            }
            .frame(height: 380)
            .clipped()
            .animation(quickMotion, value: selectedPlot)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 460, alignment: .topLeading)
        .studioCard()
    }

    private var plotPicker: some View {
        Picker("Analysis plot", selection: $selectedPlot) {
            ForEach(AnalysisPlot.allCases) { plot in
                Text(plot.rawValue).tag(plot)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .tint(.primary)
        .frame(maxWidth: 280)
    }

    private func copyGraphButton(_ take: PracticeSession) -> some View {
        StudioQuietIconButton(
            systemImage: "doc.on.doc",
            help: isGraphCopied ? "Copied" : "Copy graph as PNG",
            confirmed: isGraphCopied
        ) {
            copyAnalysisSnapshot(take)
        }
        .task(id: isGraphCopied) {
            await clearCopiedFlag(isGraphCopied) { isGraphCopied = false }
        }
    }

    @ViewBuilder
    private func activePlot(_ take: PracticeSession, highlightedRange: ClosedRange<Double>?, interactive: Bool) -> some View {
        let result = take.result
        let playbackTime = interactive ? model.playbackTime : 0
        let isPlaying = interactive && model.isPlaying
        let onSeek: ((Double) -> Void)? = interactive ? { time in
            selectedWordIndex = nil
            model.seek(to: time, autoplay: true)
        } : nil
        let onScrub: ((Double) -> Void)? = interactive ? { time in
            selectedWordIndex = nil
            model.seek(to: time)
        } : nil

        switch selectedPlot {
        case .pitch:
            LabeledLineChart(
                points: result.pitchContour,
                color: Studio.accent,
                range: pitchBounds(result),
                duration: result.metrics.duration,
                unit: "Hz",
                playbackTime: playbackTime,
                isPlaying: isPlaying,
                highlightedRange: highlightedRange,
                maxJumpSemitones: 4,
                onSeek: onSeek,
                onScrub: onScrub
            )
        case .loudness:
            LabeledLineChart(
                points: result.loudnessContour,
                color: Studio.accent,
                range: -60...0,
                duration: result.metrics.duration,
                unit: "dBFS",
                playbackTime: playbackTime,
                isPlaying: isPlaying,
                highlightedRange: highlightedRange,
                onSeek: onSeek,
                onScrub: onScrub
            )
        case .spectrum:
            ZStack {
                SpectrogramView(data: result.spectrogram)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                TimeRangeHighlight(range: highlightedRange, duration: result.metrics.duration)
                if interactive {
                    InteractiveGraphOverlay(
                        duration: result.metrics.duration,
                        playbackTime: model.playbackTime,
                        isPlaying: model.isPlaying,
                        onSeek: { time in
                            selectedWordIndex = nil
                            model.seek(to: time, autoplay: true)
                        },
                        onScrub: { time in
                            selectedWordIndex = nil
                            model.seek(to: time)
                        }
                    )
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
        guard let words = take.transcription?.words, !words.isEmpty else { return selectedWordIndex }

        // While playing, follow the playhead so highlight keeps moving after a seek.
        if model.isPlaying {
            return wordIndexAtPlayhead(words: words, time: model.playbackTime)
        }

        if let selectedWordIndex, words.indices.contains(selectedWordIndex) {
            return selectedWordIndex
        }

        return wordIndexAtPlayhead(words: words, time: model.playbackTime)
    }

    private func canStepWord(in take: PracticeSession, by delta: Int) -> Bool {
        guard let words = take.transcription?.words, !words.isEmpty else { return false }
        return steppedWordIndex(words: words, by: delta) != nil
    }

    private func stepWord(in take: PracticeSession, by delta: Int) {
        // SwiftUI arrow keyboardShortcuts can deliver the same keypress twice in one turn.
        guard !isHandlingWordStep else { return }
        isHandlingWordStep = true
        defer { Task { @MainActor in isHandlingWordStep = false } }

        guard let words = take.transcription?.words, !words.isEmpty,
              let target = steppedWordIndex(words: words, by: delta)
        else { return }

        selectedWordIndex = target
        model.seek(to: words[target].start)
    }

    private func steppedWordIndex(words: [TranscriptWord], by delta: Int) -> Int? {
        let target: Int
        if let current = wordIndexForStepping(words: words) {
            target = current + delta
        } else if delta > 0 {
            target = 0
        } else {
            return nil
        }
        guard words.indices.contains(target) else { return nil }
        return target
    }

    /// Prefer the locked selection so rapid ←/→ stay one word at a time; once
    /// playback leaves that word, fall back to the live playhead.
    private func wordIndexForStepping(words: [TranscriptWord]) -> Int? {
        if let selectedWordIndex, words.indices.contains(selectedWordIndex) {
            let word = words[selectedWordIndex]
            if !model.isPlaying || model.playbackTime <= word.end + 0.02 {
                return selectedWordIndex
            }
        }
        return wordIndexAtPlayhead(words: words, time: model.playbackTime)
    }

    /// Half-open [start, end) avoids double-counting when adjacent words share a boundary.
    private func wordIndexAtPlayhead(words: [TranscriptWord], time: TimeInterval) -> Int? {
        if let index = words.firstIndex(where: { $0.start <= time && time < $0.end }) {
            return index
        }
        if let last = words.indices.last,
           words[last].start <= time,
           time <= words[last].end {
            return last
        }
        return words.lastIndex(where: { $0.start <= time })
    }

    @ViewBuilder
    private func wordStepShortcuts(for take: PracticeSession) -> some View {
        let hasWords = !(take.transcription?.words.isEmpty ?? true)
        if hasWords {
            ZStack {
                Button("Previous word") { stepWord(in: take, by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("Next word") { stepWord(in: take, by: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    private var quickMotion: Animation? {
        StudioMotion.quick(reduceMotion: reduceMotion)
    }

    private func clearCopiedFlag(_ isCopied: Bool, clear: @escaping () -> Void) async {
        guard isCopied else { return }
        try? await Task.sleep(for: .seconds(2))
        if !Task.isCancelled { clear() }
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
