import SwiftUI
import VoiceCoachCore

struct InsightsView: View {
    @EnvironmentObject private var model: AppModel

    private var takes: [PracticeSession] { model.sessions.flatMap(\.takes) }

    var body: some View {
        StudioPage {
            VStack(alignment: .leading, spacing: 18) {
                if takes.isEmpty {
                    EmptyState(icon: "chart.line.uptrend.xyaxis", title: "Record a few takes to see trends", detail: "Insights become more useful as your local practice library grows.", actionTitle: "Start a session") {
                        model.navigate(to: .create)
                    }
                } else {
                    summaryMetrics
                    HStack(alignment: .top, spacing: 18) {
                        trendCard(title: "Pitch range", unit: "st", values: takes.compactMap { $0.result.metrics.pitchRangeSemitones }, detail: "Expressive range across saved takes")
                        trendCard(title: "Phrase ending", unit: "dB", values: takes.map { $0.result.metrics.phraseDecayDB }, detail: "End loudness relative to phrase start")
                        trendCard(title: "Non-speech", unit: "%", values: takes.map { $0.result.metrics.nonSpeechRatio * 100 }, detail: "Share of each recording without speech")
                    }
                    recentActivity
                }
            }
        }
    }

    private var summaryMetrics: some View {
        HStack(spacing: 0) {
            insightMetric("Sessions", "\(model.sessions.count)", "focused practice spaces", "folder")
            insightMetric("Takes", "\(model.totalTakeCount)", "recorded and analyzed", "waveform")
            insightMetric("Practice time", vcNumber(model.totalRecordedDuration / 60, 1), "minutes of recorded voice", "clock")
            insightMetric("Latest practice", model.sessions.first?.updatedAt.formatted(date: .abbreviated, time: .omitted) ?? "—", "stored locally", "calendar")
        }
        .padding(22)
        .studioCard(emphasized: true)
    }

    private func insightMetric(_ title: String, _ value: String, _ detail: String, _ icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Studio.accent)
                .frame(width: 42, height: 42).background(Studio.accent.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 10)).foregroundStyle(Studio.secondary)
                Text(value).font(.system(size: 23, weight: .regular)).monospacedDigit()
                Text(detail).font(.system(size: 9)).foregroundStyle(Studio.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { Rectangle().fill(Studio.line).frame(width: 1) }
    }

    private func trendCard(title: String, unit: String, values: [Double], detail: String) -> some View {
        let points = values.enumerated().map { TimePoint(time: Double($0.offset), value: $0.element) }
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        return VStack(alignment: .leading, spacing: 13) {
            SectionEyebrow(text: title)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(vcNumber(average, 1)).font(.system(size: 32, weight: .regular)).foregroundStyle(Studio.accent).monospacedDigit()
                Text(unit).font(.system(size: 10)).foregroundStyle(Studio.secondary)
                Spacer()
                Text("average").font(.system(size: 9)).foregroundStyle(Studio.secondary)
            }
            MiniSparkline(points: points).frame(height: 70)
            Text(detail).font(.system(size: 10)).foregroundStyle(Studio.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .studioCard()
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(text: "Recent activity")
            ForEach(model.sessions.prefix(5)) { session in
                Button { model.resumeSession(session.id) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: session.mode.icon).foregroundStyle(Studio.accent).frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.name).font(.system(size: 12, weight: .semibold))
                            Text("\(session.takeCount) takes · \(vcNumber(session.totalDuration, 0)) seconds recorded")
                                .font(.system(size: 9)).foregroundStyle(Studio.secondary)
                        }
                        Spacer()
                        Text(session.updatedAt.formatted(.relative(presentation: .named))).font(.system(size: 9)).foregroundStyle(Studio.secondary)
                        Image(systemName: "arrow.right").foregroundStyle(Studio.secondary)
                    }
                    .padding(15).studioCard(cornerRadius: 11)
                }.buttonStyle(.plain)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmDelete = true

    @ViewBuilder
    var body: some View {
        if snapshot {
            snapshotSettings
        } else {
            settingsForm
        }
    }

    private var settingsForm: some View {
        Form {
            Section("Sessions") {
                Toggle("Confirm before deleting sessions and takes", isOn: $confirmDelete)
                Text("Voice Coach will ask before permanently removing a recording from your local library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local Data") {
                LabeledContent("Library") {
                    Text("\(model.sessions.count) sessions, \(model.totalTakeCount) takes")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Location") {
                    Text(model.storageLocation.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("Show Library in Finder", systemImage: "folder", action: model.revealStorage)
                }
            }

            Section("Transcription") {
                transcriptionSettings
            }

            Section("Privacy and Measurements") {
                Text("Recordings, transcripts, and analysis stay on this Mac. Voice-quality values are acoustic coaching signals, not medical measurements or diagnoses.")
                    .foregroundStyle(.secondary)
                Text("Waveforms and spectrograms remain available in the app but are intentionally excluded from copied and exported JSON.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 620)
        .onAppear { model.refreshTranscriptionSetupStatus() }
    }

    private var snapshotSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice Coach Settings")
                .font(.title2.weight(.semibold))

            snapshotSection("Sessions", symbol: "rectangle.stack") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confirm before deleting sessions and takes")
                            .font(.body.weight(.medium))
                        Text("Voice Coach will ask before permanently removing a local recording.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: confirmDelete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(Studio.accent)
                }
            }

            snapshotSection("Local Data", symbol: "internaldrive") {
                LabeledContent("Library", value: "\(model.sessions.count) sessions, \(model.totalTakeCount) takes")
                Text(model.storageLocation.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            snapshotSection("Transcription", symbol: "text.bubble") {
                Text(statusTitle(for: model.transcriptionSetupStatus))
                    .font(.body.weight(.medium))
                Text(statusDetail(for: model.transcriptionSetupStatus))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            snapshotSection("Privacy and Measurements", symbol: "hand.raised") {
                Text("Recordings, transcripts, and analysis stay on this Mac. Acoustic coaching signals are not medical measurements.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Studio.background)
        .onAppear { model.refreshTranscriptionSetupStatus() }
    }

    @ViewBuilder
    private var transcriptionSettings: some View {
        let status = model.transcriptionSetupStatus
        let busy = status.isBusy || model.isRecording || model.isAnalyzing

        Text("Optional on-device transcripts use NVIDIA Parakeet through NeMo-Speech.cpp. Voice Coach downloads the runtime and model to this Mac; recordings are never uploaded.")
            .foregroundStyle(.secondary)

        LabeledContent("Status") {
            Text(statusTitle(for: status))
                .foregroundStyle(.secondary)
        }
        Text(statusDetail(for: status))
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

        if case .installing(let phase) = status {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(phase.userFacingLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        transcriptionActions(status: status, busy: busy)
    }

    @ViewBuilder
    private func transcriptionActions(status: TranscriptionSetupStatus, busy: Bool) -> some View {
        switch status {
        case .ready:
            HStack {
                Spacer()
                Button("Check for updates", action: model.startTranscriptionSetup)
                    .disabled(busy)
                Button("Show in Finder", systemImage: "folder", action: model.revealTranscriptionInstall)
            }
        case .unsupported:
            EmptyView()
        case .missing, .failed, .installing:
            HStack {
                Spacer()
                Button(status.isBusy ? "Downloading…" : "Download transcription (~714 MB)") {
                    model.startTranscriptionSetup()
                }
                .disabled(busy)
            }
        }
    }

    private func statusTitle(for status: TranscriptionSetupStatus) -> String {
        switch status {
        case .ready: "Ready"
        case .missing: "Not installed"
        case .installing: "Installing"
        case .failed: "Needs attention"
        case .unsupported: "Unavailable"
        }
    }

    private func statusDetail(for status: TranscriptionSetupStatus) -> String {
        switch status {
        case .ready(_, let modelID):
            "\(modelID) · local only"
        case .missing:
            "Acoustic analysis works without this. Download once to enable word-level transcripts."
        case .installing(let phase):
            phase.userFacingLabel
        case .failed(let message), .unsupported(let message):
            message
        }
    }

    private func snapshotSection<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .desktopPanel()
    }
}
