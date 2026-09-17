import SwiftUI
import VoiceCoachCore

struct MimicWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot

    var body: some View {
        VStack(spacing: 0) {
            StudioScroll {
                if let session = model.selectedSession, let reference = session.mimicReference {
                    VStack(alignment: .leading, spacing: 18) {
                        heading(session)
                        referenceStrip(reference)
                        if model.mimicShowingResult, let attempt = model.selectedTake {
                            MimicComparisonView(
                                reference: reference.take, attempt: attempt,
                                comparison: MimicComparison.compare(reference: reference.take, attempt: attempt)
                            )
                        } else {
                            practicePanel(session, reference: reference)
                        }
                    }
                    .frame(maxWidth: 1050, alignment: .topLeading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .top)
                } else {
                    ContentUnavailableView("Reference Unavailable", systemImage: "waveform.badge.exclamationmark", description: Text("This Mimic session needs its reference audio."))
                        .frame(maxWidth: .infinity, minHeight: 350)
                }
            }
            transport
        }
        .background {
            if !snapshot {
                HStack {
                    Button("Previous Mimic Take") { model.stepMimicTake(by: -1) }
                        .keyboardShortcut(.leftArrow, modifiers: .option)
                    Button("Next Mimic Take") { model.stepMimicTake(by: 1) }
                        .keyboardShortcut(.rightArrow, modifiers: .option)
                }
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
    }

    private func heading(_ session: CoachingSession) -> some View {
        HStack(spacing: 12) {
            Label("Mimic", systemImage: "waveform.path")
                .font(.callout.weight(.medium))
            Spacer()
            if !session.takes.isEmpty {
                if snapshot {
                    Text("Take \((session.takes.firstIndex(where: { $0.id == model.selectedTakeID }) ?? 0) + 1) of \(session.takeCount)")
                        .font(.caption)
                        .padding(7)
                        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 6))
                    Text(model.mimicShowingResult ? "Compare" : "Practice")
                        .font(.caption.weight(.semibold))
                        .padding(7)
                        .background(Studio.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Picker("Attempt", selection: Binding(
                        get: { model.selectedTakeID ?? session.latestTake!.id },
                        set: { value in model.selectTake(value) }
                    )) {
                        ForEach(Array(session.takes.enumerated()), id: \.element.id) { index, take in
                            Text("Take \(index + 1) · \((session.mimicAttemptStyles?[take.id] ?? .listenAndRepeat).title) · \(take.createdAt.formatted(date: .omitted, time: .shortened))")
                                .tag(take.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                    .disabled(model.isRecording || model.mimicPhase != .ready)

                    Picker("Workspace", selection: $model.mimicShowingResult) {
                        Text("Practice").tag(false)
                        Text("Compare").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 175)
                    .disabled(model.isRecording || model.mimicPhase != .ready)
                }
            }
        }
    }

    private func referenceStrip(_ reference: MimicReference) -> some View {
        let audioAvailable = snapshot || FileManager.default.fileExists(atPath: reference.take.audioURL.path)
        return HStack(spacing: 12) {
            Button {
                if model.isPlaying { model.stopPlayback() }
                else { model.playMimicReference() }
            } label: {
                Image(systemName: model.isPlaying && model.mimicPlaybackSource == .reference ? "stop.fill" : "play.fill")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .help("Play reference")
            .disabled(!audioAvailable || model.isRecording || model.isAnalyzing || model.mimicPhase == .countIn(1) || model.mimicPhase == .countIn(2))

            VStack(alignment: .leading, spacing: 2) {
                SectionEyebrow(text: "Reference")
                Text(reference.sourceName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            Spacer()
            Text(vcDuration(reference.take.result.metrics.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Studio.secondary)
        }
        .padding(14)
        .desktopPanel()
        .overlay(alignment: .bottomLeading) {
            if !audioAvailable {
                Text("Reference audio is missing. Previous takes remain available in Take Analysis.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)
            }
        }
    }

    private func practicePanel(_ session: CoachingSession, reference: MimicReference) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionEyebrow(text: model.isRecording ? "Recording" : "Listen, then make it yours")
            if let transcription = reference.take.transcription {
                MimicTranscriptText(
                    transcription: transcription,
                    activeIndex: model.isPlaying && model.mimicPlaybackSource == .reference
                        ? transcription.words.firstIndex(where: { model.playbackTime >= $0.start && model.playbackTime < $0.end }) : nil,
                    activeColor: Studio.accent
                ) { _, word in model.seekMimic(source: .reference, to: word.start) }
                    .font(.system(size: 28, weight: .medium))
                    .lineSpacing(7)
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            } else {
                ContentUnavailableView("Transcript Unavailable", systemImage: "text.quote", description: Text("You can listen and practise without transcription. Word-by-word comparison will be unavailable."))
                    .frame(maxWidth: .infinity, minHeight: 130)
            }

            Divider()

            if snapshot {
                HStack(spacing: 10) {
                    ForEach(MimicStyle.allCases) { style in
                        Text(style.title)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(session.mimicStyle == style ? Studio.accent.opacity(0.18) : Studio.surface, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            } else {
                Picker("Practice style", selection: Binding(
                    get: { session.mimicStyle ?? .listenAndRepeat },
                    set: { value in model.updateMimicStyle(value) }
                )) {
                    ForEach(MimicStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .disabled(model.mimicPhase != .ready)
            }

            Text(session.mimicStyle == .speakAlong
                 ? "Use headphones for a clean take. Speaker sound can enter your microphone while the reference plays."
                 : "Listen to the reference, then record your own version.")
                .font(.callout)
                .foregroundStyle(Studio.secondary)

            if model.isRecording {
                HStack(spacing: 12) {
                    Circle().fill(.red).frame(width: 9, height: 9)
                    Text("Recording · \(vcDuration(model.elapsed))")
                        .font(.headline.monospacedDigit())
                    LiveMeterView(level: model.liveLevel)
                        .frame(maxWidth: 260)
                }
            } else if case .countIn(let number) = model.mimicPhase {
                Text("Starting in \(number)…")
                    .font(.headline.monospacedDigit())
            } else if model.mimicPhase == .playingReference {
                Text("Listen to the reference. Recording starts after a short count-in.")
                    .font(.callout)
                    .foregroundStyle(Studio.secondary)
            } else if model.isAnalyzing || model.mimicPhase == .analyzing {
                ProgressView("Saving and analyzing on this Mac…")
            }
            if model.hasPendingMimicWork {
                Divider()
                Text("This recording is on your Mac but needs to be saved to the library.")
                    .font(.callout)
                HStack {
                    Button("Retry Save / Analysis") { model.retryPendingMimicWork() }
                    Button("Reveal Audio") { model.revealPendingMimicAudio() }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .desktopPanel()
    }

    private var transport: some View {
        Group {
            if model.mimicShowingResult, let session = model.selectedSession,
               let reference = session.mimicReference, let attempt = model.selectedTake {
                compareTransport(reference: reference.take, attempt: attempt)
            } else {
                practiceTransport
            }
        }
    }

    private func compareTransport(reference: PracticeSession, attempt: PracticeSession) -> some View {
        let comparison = MimicComparison.compare(reference: reference, attempt: attempt)
        return VStack(spacing: 0) {
            Rectangle()
                .fill(Studio.line)
                .frame(height: 1)

            MimicComparePlaybackRow(
                reference: reference,
                attempt: attempt,
                comparison: comparison
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
    }

    private var practiceTransport: some View {
        HStack(spacing: 12) {
            if case .countIn = model.mimicPhase {
                Button("Cancel Count-in") { model.cancelMimicCountIn() }
            } else if model.mimicPhase == .playingReference {
                Button("Cancel") { model.stopPlayback() }
                    .keyboardShortcut(.space, modifiers: [])
            } else if model.isRecording {
                Button("Stop Recording") { model.recordButtonPressed() }
                    .tint(.red)
                    .studioGlassButton(prominent: true)
            } else {
                Button("Listen") { model.toggleMimicPlayback() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(model.isAnalyzing || model.mimicPhase != .ready || model.hasPendingMimicWork)
                Button("Start Practice") { model.startMimicPractice() }
                    .studioGlassButton(prominent: true)
                    .disabled(model.isAnalyzing || model.isRequestingPermission || model.isPlaying || model.mimicPhase != .ready || model.hasPendingMimicWork)
                if model.selectedSession?.mimicStyle == .listenAndRepeat {
                    Button("Record Now") { model.startMimicPractice(skipReference: true) }
                        .disabled(model.isAnalyzing || model.isPlaying || model.hasPendingMimicWork)
                }
            }
            Spacer()
            if let session = model.selectedSession, let take = session.latestTake, !model.isRecording {
                Button("Review Take \(session.takeCount)") { model.selectTake(take.id) }
                    .disabled(model.isAnalyzing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}

struct MimicInspector: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        StudioScroll {
            if let session = model.selectedSession, let reference = session.mimicReference {
                VStack(alignment: .leading, spacing: 16) {
                    SectionEyebrow(text: model.mimicShowingResult ? "Comparison" : "Practice")
                    Text(session.name).font(.headline)
                    Text("Reference · \(vcDuration(reference.take.result.metrics.duration))")
                        .font(.caption).foregroundStyle(Studio.secondary)
                    Divider()
                    if model.mimicShowingResult, let take = model.selectedTake {
                        let takeNumber = (session.takes.firstIndex(where: { $0.id == take.id }) ?? 0) + 1
                        Text("Take \(takeNumber)")
                            .font(.title3.weight(.semibold))
                        Text("Listen to both versions, then try again when you are ready.")
                            .font(.callout).foregroundStyle(Studio.secondary)
                        Divider()
                        Button("Try Again") { model.startMimicPractice() }
                            .studioGlassButton(prominent: true)
                            .disabled(model.isPlaying || model.isAnalyzing)
                        Button("Open Take Analysis") { model.openTake(sessionID: session.id, takeID: take.id) }
                    } else {
                        Text("Microphone: System Input")
                            .font(.callout)
                        LiveMeterView(level: model.liveLevel).frame(height: 18)
                        Text("A two-second count-in precedes recording.")
                            .font(.caption).foregroundStyle(Studio.secondary)
                        Divider()
                        Text("Reference volume")
                            .font(.callout)
                        Slider(value: $model.mimicReferenceVolume, in: 0.1...1)
                        if session.mimicStyle == .speakAlong {
                            Label("Headphones reduce reference sound entering the microphone.", systemImage: "headphones")
                                .font(.caption)
                                .foregroundStyle(Studio.secondary)
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}
