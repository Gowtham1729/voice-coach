import SwiftUI
import VoiceCoachCore

struct PracticeView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("voiceCoach.showPromptByDefault") private var showPrompt = true
    @State private var transcriptExpanded = false
    @State private var analysisExpanded = false
    @State private var exportExpanded = false

    var body: some View {
        StudioPage {
            if let session = model.selectedSession {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Studio   /   \(session.name)   /   Practice")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Studio.secondary)
                        Spacer()
                        Button { model.navigate(to: AppDestination.studio) } label: {
                            Label("End session", systemImage: "stop.fill")
                        }
                        .buttonStyle(StudioButtonStyle())
                        .disabled(model.isRecording || model.isAnalyzing)
                    }

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 9) {
                                Circle().fill(model.isRecording ? Color.orange : Studio.accent).frame(width: 6, height: 6)
                                SectionEyebrow(text: model.isRecording ? "Recording in progress" : "Practice mode")
                            }
                            Text(stageTitle(session))
                                .font(.system(size: 38, weight: .regular)).tracking(-1.6).lineSpacing(-3)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(stageDetail(session))
                                .font(.system(size: 13)).foregroundStyle(Studio.secondary)
                        }
                        Spacer()
                        if model.isRecording {
                            VStack(alignment: .trailing, spacing: 10) {
                                Text(vcDuration(model.elapsed)).font(.system(size: 30, weight: .light, design: .monospaced)).foregroundStyle(Studio.accent)
                                LiveMeterView(level: model.liveLevel).frame(width: 280)
                                Text("MIC LEVEL  ·  \(Int(model.liveLevel)) dBFS  ·  90s maximum")
                                    .font(.system(size: 8, design: .monospaced)).foregroundStyle(Studio.secondary)
                            }
                        }
                    }

                    if let take = model.selectedTake {
                        HStack(alignment: .top, spacing: 18) {
                            latestTakeCard(take, session: session)
                            coachingCard(take, previous: model.previousTake)
                        }
                        .frame(minHeight: 206)
                    } else {
                        readyCard(session)
                    }

                    HStack(spacing: 12) {
                        Button(action: model.recordButtonPressed) {
                            HStack(spacing: 14) {
                                if model.isAnalyzing { ProgressView().controlSize(.small) }
                                else { Image(systemName: model.isRecording ? "stop.fill" : "mic.fill") }
                                Text(recordButtonTitle(for: session))
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(StudioButtonStyle(prominent: true, destructive: model.isRecording))
                        .keyboardShortcut(.space, modifiers: [])
                        .disabled(model.isAnalyzing || model.isRequestingPermission)
                        .overlay(alignment: .trailing) {
                            if !model.isRecording && !model.isAnalyzing {
                                Text("SPACE").font(.system(size: 9, design: .monospaced)).tracking(1.5)
                                    .foregroundStyle(Studio.secondary).padding(.trailing, 18)
                            }
                        }

                        Button(action: model.importClip) {
                            Label("Import audio or video", systemImage: "square.and.arrow.down")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(StudioButtonStyle())
                        .frame(maxWidth: 270)
                        .disabled(model.isRecording || model.isAnalyzing || model.isRequestingPermission)
                    }

                    Text("Import a phone recording, audio clip, or video to compare. The audio is extracted and kept only on this Mac.")
                        .font(.system(size: 10))
                        .foregroundStyle(Studio.secondary)

                    if !session.takes.isEmpty { takeHistory(session) }
                    details
                    PrivacyFooter()
                }
            } else {
                EmptyState(icon: "exclamationmark.triangle", title: "Session not found", detail: "This session is no longer in your local library.", actionTitle: "Back to studio") {
                    model.navigate(to: AppDestination.studio)
                }
            }
        }
    }

    private func stageDetail(_ session: CoachingSession) -> String {
        if model.isRecording { return "Take your time. Leave a little space between thoughts." }
        if model.isAnalyzing { return "Measuring pitch, loudness, pauses and voice quality on this Mac." }
        if !session.prompt.isEmpty { return "Focus on one thing at a time. Your prompt is ready below." }
        return "Take another 10–30 seconds. Focus on one thing at a time."
    }

    private func stageTitle(_ session: CoachingSession) -> String {
        if model.isRecording { return "Speak naturally.\nYour voice is being heard." }
        if model.isAnalyzing { return "Listening closely.\nYour take is being analyzed." }
        if session.takes.isEmpty { return "Begin with one take.\nThere is nothing to perfect." }
        return "Keep going.\nSmall changes make a real difference."
    }

    private func recordButtonTitle(for session: CoachingSession) -> String {
        if model.isRecording { return "Finish recording" }
        if model.isAnalyzing { return "Analyzing take…" }
        if session.takes.isEmpty { return "Record first take" }
        return "Record next take"
    }

    private func readyCard(_ session: CoachingSession) -> some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 13) {
                SectionEyebrow(text: "A place to begin")
                Text(displayedPrompt(for: session))
                    .font(.system(size: 20, weight: .regular, design: .serif)).lineSpacing(5)
                Text("Read this aloud, or use it as a starting point.")
                    .font(.system(size: 10)).foregroundStyle(Studio.secondary)
            }
            Spacer()
            VoiceSculpture(recording: model.isRecording, level: model.liveLevel).frame(width: 250, height: 180)
        }
        .padding(24)
        .studioCard(emphasized: true)
    }

    private func defaultPrompt(for mode: PracticeMode) -> String {
        switch mode {
        case .general: "I want to speak with a little more intention, take my time, and let my voice be heard."
        case .prompt: "A thoughtful pause can give an idea room to land before the next one begins."
        case .freeSpeaking: "Tell a short story about something that surprised you recently."
        }
    }

    private func displayedPrompt(for session: CoachingSession) -> String {
        guard showPrompt else {
            return "Take a comfortable breath, choose one idea, and speak in your usual voice."
        }
        return session.prompt.isEmpty ? defaultPrompt(for: session.mode) : session.prompt
    }

    private func latestTakeCard(_ take: PracticeSession, session: CoachingSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    SectionEyebrow(text: "Latest take")
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Take \(takeNumber(take, in: session))").font(.system(size: 18, weight: .semibold))
                        if take.takeSource != .recorded {
                            Label(take.takeSource.title, systemImage: take.takeSource.icon)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Studio.accent)
                        }
                        Text("\(take.createdAt.formatted(date: .omitted, time: .shortened))  ·  \(vcNumber(take.result.metrics.duration, 1))s")
                            .font(.system(size: 10)).foregroundStyle(Studio.secondary)
                    }
                }
                Spacer()
                Button { model.review(sessionID: session.id, takeID: take.id) } label: {
                    Label("Full review", systemImage: "arrow.up.right")
                }.buttonStyle(StudioButtonStyle())
            }
            TakePlaybackRow(take: take, large: true)
            if let text = take.transcription?.text {
                Text("“\(text)”").font(.system(size: 12, design: .serif)).foregroundStyle(Studio.secondary).lineLimit(2)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private func coachingCard(_ take: PracticeSession, previous: PracticeSession?) -> some View {
        let coaching = coachingMessage(take.result.metrics)
        return VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 20)).foregroundStyle(Studio.accent)
                    .frame(width: 48, height: 48)
                    .background(Studio.accent.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 7) {
                    SectionEyebrow(text: "One thing to try")
                    Text(coaching.title).font(.system(size: 18, weight: .semibold)).lineSpacing(2)
                    Text(coaching.detail).font(.system(size: 11)).foregroundStyle(Studio.secondary).lineSpacing(4)
                }
            }
            Rectangle().fill(Studio.line).frame(height: 1)
            HStack(spacing: 0) {
                comparisonMetric("Phrase ending", vcSigned(take.result.metrics.phraseDecayDB), "dB", delta: previous.map { take.result.metrics.phraseDecayDB - $0.result.metrics.phraseDecayDB })
                comparisonMetric("Pitch range", vcOptional(take.result.metrics.pitchRangeSemitones), "st", delta: delta(take.result.metrics.pitchRangeSemitones, previous?.result.metrics.pitchRangeSemitones))
                comparisonMetric("Pauses", "\(take.result.metrics.internalPauseCount)", "", delta: previous.map { Double(take.result.metrics.internalPauseCount - $0.result.metrics.internalPauseCount) }, positiveGood: false)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard(emphasized: true)
    }

    private func comparisonMetric(_ title: String, _ value: String, _ unit: String, delta: Double?, positiveGood: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(Studio.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 24, weight: .regular)).monospacedDigit()
                Text(unit).font(.system(size: 9)).foregroundStyle(Studio.secondary)
            }
            if let delta { DeltaLabel(value: delta, unit: unit, positiveIsGood: positiveGood) }
            else { Text("First take").font(.system(size: 9)).foregroundStyle(Studio.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func takeHistory(_ session: CoachingSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Take history")
            HStack(spacing: 10) {
                ForEach(Array(session.takes.suffix(5).enumerated()), id: \.element.id) { offset, take in
                    let index = session.takes.count - min(session.takes.count, 5) + offset
                    Button { model.selectTake(take.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: model.selectedTakeID == take.id && model.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 9)).frame(width: 28, height: 28).background(Studio.line, in: Circle())
                            Text("Take \(index + 1)").font(.system(size: 11, weight: .medium))
                            if take.takeSource != .recorded {
                                Image(systemName: take.takeSource.icon)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Studio.accent)
                            }
                            Text("\(vcNumber(take.result.metrics.duration, 1))s").font(.system(size: 9, design: .monospaced)).foregroundStyle(Studio.secondary)
                            MiniSparkline(points: take.result.pitchContour).frame(width: 70, height: 24)
                        }
                        .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 46)
                        .background(model.selectedTakeID == take.id ? Studio.accent.opacity(0.08) : Studio.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(model.selectedTakeID == take.id ? Studio.accent : Studio.line))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var details: some View {
        VStack(spacing: 8) {
            disclosure("Transcript", icon: "doc.text", subtitle: "Full text from this take", isExpanded: $transcriptExpanded) {
                Text(model.selectedTake?.transcription?.text ?? model.transcriptionNotice ?? "No transcript is available for this take.")
                    .font(.system(size: 12, design: .serif)).foregroundStyle(Studio.secondary).textSelection(.enabled)
            }
            disclosure("Detailed analysis", icon: "chart.bar", subtitle: "See the objective measurements for this take", isExpanded: $analysisExpanded) {
                if let metrics = model.selectedTake?.result.metrics {
                    HStack {
                        MetricTile(title: "Median pitch", value: vcOptional(metrics.medianPitchHz, 0), unit: "Hz", detail: "Central pitch")
                        MetricTile(title: "Pitch range", value: vcOptional(metrics.pitchRangeSemitones), unit: "st", detail: "5th–95th percentile")
                        MetricTile(title: "Loudness", value: vcNumber(metrics.meanLoudnessDBFS), unit: "dBFS", detail: "Active speech")
                        MetricTile(title: "SNR", value: vcNumber(metrics.snrDB), unit: "dB", detail: "Recording quality")
                    }
                }
            }
            disclosure("Export", icon: "square.and.arrow.up", subtitle: "Save or copy this take", isExpanded: $exportExpanded) {
                HStack {
                    Button("Copy compact JSON", action: model.copyCompactReport).buttonStyle(StudioButtonStyle())
                    Button("Copy word-level JSON", action: model.copyReport).buttonStyle(StudioButtonStyle())
                    Button("Export audio + JSON", action: model.exportCurrent).buttonStyle(StudioButtonStyle())
                }
            }
        }
    }

    private func disclosure<Content: View>(_ title: String, icon: String, subtitle: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { isExpanded.wrappedValue.toggle() } } label: {
                HStack(spacing: 14) {
                    Image(systemName: icon).foregroundStyle(Studio.accent).frame(width: 26)
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(Studio.secondary)
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if isExpanded.wrappedValue { content().padding(.leading, 40).padding(.bottom, 8) }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .studioCard(cornerRadius: 12)
    }

    private func takeNumber(_ take: PracticeSession, in session: CoachingSession) -> Int {
        (session.takes.firstIndex(where: { $0.id == take.id }) ?? 0) + 1
    }

    private func delta(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs else { return nil }
        return lhs - rhs
    }

    private func coachingMessage(_ metrics: VoiceMetrics) -> (title: String, detail: String) {
        if metrics.phraseDecayDB < -3 {
            return ("Add a bit more energy at the end of your sentences.", "Your phrase endings are falling. Try lifting the last one or two words slightly so the thought stays open and clear.")
        }
        if (metrics.pitchRangeSemitones ?? 0) < 6 {
            return ("Let one important word carry more shape.", "Your pitch range is compact. Choose a key word and allow a little more natural movement around it.")
        }
        if metrics.nonSpeechRatio > 0.45 {
            return ("Connect the thought before the next pause.", "There is generous space between phrases. Try completing one full idea before you pause again.")
        }
        return ("Keep this ease and clarity.", "The main acoustic signals are balanced in this take. Repeat it once and notice what remains consistent.")
    }
}
