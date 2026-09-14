import AppKit
import SwiftUI
import VoiceCoachCore

struct ReviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var plotSelection
    @State private var selectedPlot: AnalysisPlot = .pitch
    @State private var selectedWordIndex: Int?
    @State private var comparisonTakeID: UUID?
    @State private var editingName = false
    @State private var draftName = ""
    @State private var reportExpanded = false
    @State private var isGraphCopied = false
    @State private var takePendingDelete: UUID?
    @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmBeforeDelete = true

    var body: some View {
        StudioPage(maxWidth: 1560) {
            if let session = model.selectedSession, let take = model.selectedTake {
                VStack(alignment: .leading, spacing: 18) {
                    topBar(session, take: take)
                    HStack(alignment: .top, spacing: 18) {
                        transcriptCard(take)
                            .frame(width: 540)
                        VStack(spacing: 18) {
                            measurementsCard(take, comparison: comparisonTake(in: session, excluding: take.id))
                            analysisCard(take)
                        }
                    }
                    structuredDataBar
                    PrivacyFooter()
                }
                .onAppear {
                    draftName = session.name
                    if comparisonTakeID == nil { comparisonTakeID = model.previousTake?.id }
                }
                .onChange(of: model.selectedTakeID) { _, _ in selectedWordIndex = nil }
                .modifier(DeleteTakeDialog(takeID: $takePendingDelete) { id in
                    if comparisonTakeID == id { comparisonTakeID = nil }
                    model.deleteTake(id)
                })
            } else {
                EmptyState(icon: "waveform", title: "Take not found", detail: "Choose another session from your local library.", actionTitle: "View sessions") {
                    model.navigate(to: AppDestination.sessions)
                }
            }
        }
    }

    private func topBar(_ session: CoachingSession, take: PracticeSession) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                BackButton(title: "Back to session") { model.resumeSession(session.id) }
                SectionEyebrow(text: session.name)
                HStack(spacing: 10) {
                    if editingName {
                        TextField("Session name", text: $draftName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 28, weight: .regular))
                            .frame(maxWidth: 420)
                            .onSubmit { commitName(session.id) }
                    } else {
                        Text("Your voice, in focus.").font(.system(size: 30, weight: .regular)).tracking(-1)
                    }
                    Button {
                        editingName.toggle()
                        if !editingName { commitName(session.id) }
                    } label: { Image(systemName: editingName ? "checkmark" : "pencil") }
                    .buttonStyle(.plain).foregroundStyle(Studio.accent)
                }
                Text("\(session.createdAt.formatted(date: .abbreviated, time: .omitted))  ·  \(session.takeCount) takes  ·  \(vcNumber(take.result.metrics.duration, 1))s")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Studio.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                Button { model.selectAdjacentTake(offset: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(StudioButtonStyle())
                if snapshot {
                    Text("Take \((session.takes.firstIndex(where: { $0.id == take.id }) ?? 0) + 1) of \(session.takeCount)")
                        .font(.system(size: 11, weight: .medium)).frame(width: 135, height: 36).studioCard(cornerRadius: 18)
                } else {
                    Picker("Take", selection: Binding(
                        get: { model.selectedTakeID ?? take.id },
                        set: { model.selectTake($0) }
                    )) {
                        ForEach(Array(session.takes.enumerated()), id: \.element.id) { index, item in
                            Text("Take \(index + 1) of \(session.takeCount)").tag(item.id)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 145)
                }
                Button { model.selectAdjacentTake(offset: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(StudioButtonStyle())
                Button { requestDelete(take.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(StudioButtonStyle(destructive: true))
                .help("Delete this take")
                .disabled(model.isPlaying || model.isAnalyzing)
                if session.takeCount > 1 {
                    if snapshot {
                        Text(comparisonLabel(session))
                            .font(.system(size: 11, weight: .medium)).frame(width: 180, height: 36).studioCard(cornerRadius: 18)
                    } else {
                        Picker("Compare with", selection: $comparisonTakeID) {
                            Text("No comparison").tag(UUID?.none)
                            ForEach(Array(session.takes.enumerated()), id: \.element.id) { index, item in
                                if item.id != take.id { Text("Compare with Take \(index + 1)").tag(Optional(item.id)) }
                            }
                        }
                        .pickerStyle(.menu).frame(width: 190)
                    }
                }
            }
        }
    }

    private func transcriptCard(_ take: PracticeSession) -> some View {
        let highlightedWordIndex = highlightedWordIndex(in: take)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionEyebrow(text: "Transcript")
                Spacer()
                Text("\(take.transcription?.words.count ?? 0) words  ·  \(vcNumber(take.result.metrics.duration, 1))s")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Studio.secondary)
            }
            if let transcription = take.transcription {
                ReviewTranscriptPane(
                    transcription: transcription,
                    highlightedWordIndex: highlightedWordIndex,
                    isPlaying: model.isPlaying,
                    reduceMotion: reduceMotion
                ) { index, word in
                    selectedWordIndex = selectedWordIndex == index ? nil : index
                    model.seek(to: word.start)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "text.badge.xmark").font(.system(size: 28)).foregroundStyle(Studio.secondary)
                    Text(model.transcriptionNotice ?? "A transcript was not available for this take.")
                        .font(.system(size: 11)).foregroundStyle(Studio.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 50)
            }
            Spacer(minLength: 8)
            Rectangle().fill(Studio.line).frame(height: 1)
            TakePlaybackRow(take: take, spaceShortcut: true)
        }
        .padding(22)
        .frame(minHeight: 590, alignment: .topLeading)
        .studioCard()
    }

    private func measurementsCard(_ take: PracticeSession, comparison: PracticeSession?) -> some View {
        let metrics = take.result.metrics
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionEyebrow(text: "Key measurements")
                Spacer()
                Label("Measured on this take", systemImage: "info.circle")
                    .font(.system(size: 10)).foregroundStyle(Studio.secondary)
            }
            HStack(alignment: .top, spacing: 0) {
                reviewMetric("Median pitch", vcOptional(metrics.medianPitchHz, 0), "Hz", comparisonDelta(metrics.medianPitchHz, comparison?.result.metrics.medianPitchHz), "Central pitch")
                reviewMetric("Pitch range", vcOptional(metrics.pitchRangeSemitones), "st", comparisonDelta(metrics.pitchRangeSemitones, comparison?.result.metrics.pitchRangeSemitones), "5th–95th percentile")
                reviewMetric("Mean loudness", vcNumber(metrics.meanLoudnessDBFS), "dBFS", comparison.map { metrics.meanLoudnessDBFS - $0.result.metrics.meanLoudnessDBFS }, "Active speech")
                reviewMetric("Phrase ending", vcSigned(metrics.phraseDecayDB), "dB", comparison.map { metrics.phraseDecayDB - $0.result.metrics.phraseDecayDB }, "End vs. start")
                reviewMetric("HNR estimate", vcOptional(metrics.hnrDB), "dB", comparisonDelta(metrics.hnrDB, comparison?.result.metrics.hnrDB), "Periodicity proxy")
                reviewMetric("Pauses", "\(metrics.internalPauseCount)", "", comparison.map { Double(metrics.internalPauseCount - $0.result.metrics.internalPauseCount) }, "\(vcNumber(metrics.nonSpeechRatio * 100, 0))% non-speech")
            }
        }
        .padding(22)
        .studioCard()
    }

    private func reviewMetric(_ title: String, _ value: String, _ unit: String, _ delta: Double?, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(Studio.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 27, weight: .regular)).foregroundStyle(Studio.accent).tracking(-0.7).monospacedDigit()
                Text(unit).font(.system(size: 9)).foregroundStyle(Studio.secondary)
            }
            if let delta { Text("\(delta >= 0 ? "+" : "")\(vcNumber(delta, 1)) vs comparison").font(.system(size: 8)).foregroundStyle(Studio.secondary) }
            else { Text(detail).font(.system(size: 8)).foregroundStyle(Studio.secondary) }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { Rectangle().fill(Studio.line).frame(width: 1) }
    }

    private func analysisCard(_ take: PracticeSession) -> some View {
        let highlightedRange = selectedRange(take)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionEyebrow(text: "Voice analysis")
                Spacer()
                HStack(spacing: 2) {
                    ForEach(AnalysisPlot.allCases) { plot in
                        Button {
                            withAnimation(plotAnimation) { selectedPlot = plot }
                        } label: {
                            Text(plot.rawValue).font(.system(size: 10, weight: .medium))
                                .frame(width: 82, height: 28)
                                .background {
                                    if selectedPlot == plot {
                                        Capsule()
                                            .fill(Studio.accent)
                                            .matchedGeometryEffect(id: "analysis-plot-selection", in: plotSelection)
                                    }
                                }
                                .foregroundStyle(selectedPlot == plot ? Studio.background : Studio.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(3).overlay(Capsule().stroke(Studio.line))
                Button(action: { copyAnalysisSnapshot(take) }) {
                    Label(isGraphCopied ? "Copied" : "Copy graph", systemImage: isGraphCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(StudioButtonStyle())
                .help("Copy the current graph and waveform as a PNG for visual-capable AI tools")
                .task(id: isGraphCopied) {
                    guard isGraphCopied else { return }
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled { isGraphCopied = false }
                }
            }
            ZStack {
                activePlot(take, highlightedRange: highlightedRange, interactive: true)
                    .id(selectedPlot)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
            .animation(plotAnimation, value: selectedPlot)
            .frame(height: 220)
            Rectangle().fill(Studio.line).frame(height: 1)
            AlignedWaveformRow(
                points: take.result.waveform,
                duration: take.result.metrics.duration,
                playbackTime: model.playbackTime,
                isPlaying: model.isPlaying,
                highlightedRange: highlightedRange,
                onSeek: { model.seek(to: $0, autoplay: true) },
                onScrub: { model.seek(to: $0) }
            ).frame(height: 44)
        }
        .padding(22)
        .frame(minHeight: 365)
        .studioCard()
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
                SpectrogramView(data: result.spectrogram).clipShape(RoundedRectangle(cornerRadius: 6))
                TimeRangeHighlight(range: highlightedRange, duration: result.metrics.duration)
                if interactive {
                    InteractiveGraphOverlay(duration: result.metrics.duration, playbackTime: model.playbackTime, isPlaying: model.isPlaying, onSeek: { model.seek(to: $0, autoplay: true) }, onScrub: { model.seek(to: $0) })
                }
            }
        }
    }

    private var structuredDataBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "doc.text").foregroundStyle(Studio.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Structured voice data").font(.system(size: 12, weight: .semibold))
                    Text("Objective data for this take; visual payloads stay in the UI.").font(.system(size: 9)).foregroundStyle(Studio.secondary)
                }
                Spacer()
                Button("Copy compact JSON", action: model.copyCompactReport).buttonStyle(StudioButtonStyle())
                Button("Copy word-level JSON", action: model.copyReport).buttonStyle(StudioButtonStyle())
                Button(action: model.exportCurrent) { Image(systemName: "square.and.arrow.up") }.buttonStyle(StudioButtonStyle())
                Button { reportExpanded.toggle() } label: { Image(systemName: "ellipsis") }.buttonStyle(StudioButtonStyle())
            }
            if reportExpanded {
                TextEditor(text: .constant(model.report))
                    .font(.system(size: 10, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(height: 240)
                    .background(Studio.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(18)
        .studioCard(cornerRadius: 12)
    }

    private func commitName(_ id: UUID) {
        model.renameSession(id, to: draftName)
        editingName = false
    }

    private func requestDelete(_ takeID: UUID) {
        if confirmBeforeDelete { takePendingDelete = takeID }
        else {
            if comparisonTakeID == takeID { comparisonTakeID = nil }
            model.deleteTake(takeID)
        }
    }

    private func comparisonTake(in session: CoachingSession, excluding id: UUID) -> PracticeSession? {
        guard let comparisonTakeID, comparisonTakeID != id else { return nil }
        return session.takes.first { $0.id == comparisonTakeID }
    }

    private func comparisonLabel(_ session: CoachingSession) -> String {
        guard let comparisonTakeID,
              let index = session.takes.firstIndex(where: { $0.id == comparisonTakeID })
        else { return "No comparison" }
        return "Compare with Take \(index + 1)"
    }

    private func comparisonDelta(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs else { return nil }
        return lhs - rhs
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
        if model.isPlaying {
            return words.firstIndex { $0.start <= model.playbackTime && model.playbackTime <= $0.end }
        }
        return selectedWordIndex
    }

    private var plotAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.28, extraBounce: 0)
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
                    .font(.system(size: 10, weight: .semibold)).tracking(1.8).foregroundStyle(Studio.secondary)
                Spacer()
                Text("\(vcNumber(take.result.metrics.duration, 1))s")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Studio.secondary)
            }
            activePlot(take, highlightedRange: selectedRange(take), interactive: false)
                .frame(height: 225)
            Rectangle().fill(Studio.line).frame(height: 1)
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
