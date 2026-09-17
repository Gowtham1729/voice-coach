import SwiftUI
import VoiceCoachCore

private enum SettingsPane: String {
    case general
    case transcription
    case library
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @AppStorage("voiceCoach.settingsPane") private var pane = SettingsPane.general
    @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmDelete = true

    private var transcriptionBusy: Bool {
        model.systemTranscriptionStatus.isBusy
            || model.transcriptionSetupStatus.isBusy
            || model.isRecording
            || model.isAnalyzing
    }

    var body: some View {
        Group {
            if snapshot {
                snapshotSettings
            } else {
                liveSettings
            }
        }
        .onAppear {
            model.refreshTranscriptionSetupStatus()
            model.refreshSystemTranscriptionStatus()
        }
    }

    private var liveSettings: some View {
        TabView(selection: $pane) {
            Tab("General", systemImage: "gearshape", value: SettingsPane.general) {
                generalPane
            }
            Tab("Transcription", systemImage: "waveform", value: SettingsPane.transcription) {
                transcriptionPane
            }
            Tab("Library", systemImage: "internaldrive", value: SettingsPane.library) {
                libraryPane
            }
        }
        .frame(width: 480, height: 380)
    }

    private var generalPane: some View {
        Form {
            Section {
                Toggle("Confirm before deleting", isOn: $confirmDelete)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ask before permanently removing sessions or takes.")
                    Text("Recordings stay on this Mac. Voice-quality values are coaching signals, not medical diagnoses.")
                }
            }
        }
        .settingsPaneChrome()
    }

    private var transcriptionPane: some View {
        let systemStatus = model.systemTranscriptionStatus
        let parakeetStatus = model.transcriptionSetupStatus
        let busy = transcriptionBusy

        return Form {
            Section {
                Picker("Engine", selection: engineSelection) {
                    Text("System").tag(TranscriptionEnginePreference.system)
                    Text("Parakeet").tag(TranscriptionEnginePreference.parakeet)
                }
                .pickerStyle(.radioGroup)
                .disabled(busy)
            } footer: {
                Text(model.transcriptionEngine.settingsFooter)
            }

            Section {
                LabeledContent("Status", value: systemStatus.title)
                if case .downloading = systemStatus {
                    progressRow("Downloading…")
                }
                if case .needsDownload = systemStatus {
                    Button("Download Model…") {
                        model.ensureSystemTranscriptionAssets()
                    }
                    .disabled(busy)
                }
            } header: {
                Text("System")
            } footer: {
                Text(systemStatus.settingsFooter)
                    .textSelection(.enabled)
            }

            Section {
                LabeledContent("Status", value: parakeetStatus.title)
                if case .installing(let phase) = parakeetStatus {
                    progressRow(phase.userFacingLabel)
                }
                parakeetButtons(status: parakeetStatus, busy: busy)
            } header: {
                Text("Parakeet")
            } footer: {
                Text(parakeetStatus.settingsFooter)
                    .textSelection(.enabled)
            }
        }
        .settingsPaneChrome()
    }

    private var libraryPane: some View {
        Form {
            Section {
                LabeledContent("Sessions", value: "\(model.sessions.count)")
                LabeledContent("Takes", value: "\(model.totalTakeCount)")
                Button("Show in Finder…", systemImage: "folder", action: model.revealStorage)
            } footer: {
                Text(model.storageLocation.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .settingsPaneChrome()
    }

    private var engineSelection: Binding<TranscriptionEnginePreference> {
        Binding(
            get: { model.transcriptionEngine },
            set: { model.setTranscriptionEngine($0) }
        )
    }

    private func progressRow(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(label).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func parakeetButtons(status: TranscriptionSetupStatus, busy: Bool) -> some View {
        switch status {
        case .ready:
            Button("Check for Updates…", action: model.startTranscriptionSetup)
                .disabled(busy)
            Button("Show in Finder…", systemImage: "folder", action: model.revealTranscriptionInstall)
        case .unsupported:
            EmptyView()
        case .missing, .failed, .installing:
            Button(status.isBusy ? "Downloading…" : "Download… (~714 MB)") {
                model.startTranscriptionSetup()
            }
            .disabled(busy)
        }
    }

    private var snapshotSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Voice Coach Settings")
                .font(.title2.weight(.semibold))

            snapshotCard("General", symbol: "gearshape") {
                HStack {
                    Text("Confirm before deleting")
                    Spacer()
                    Image(systemName: confirmDelete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(Studio.accent)
                }
                Text("Recordings stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            snapshotCard("Transcription", symbol: "waveform") {
                Text(model.transcriptionEngine.title)
                    .font(.body.weight(.medium))
                Text("System · \(model.systemTranscriptionStatus.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Parakeet · \(model.transcriptionSetupStatus.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            snapshotCard("Library", symbol: "internaldrive") {
                LabeledContent("Sessions", value: "\(model.sessions.count)")
                LabeledContent("Takes", value: "\(model.totalTakeCount)")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Studio.background)
    }

    private func snapshotCard<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .desktopPanel()
    }
}

private extension View {
    func settingsPaneChrome() -> some View {
        formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private extension TranscriptionEnginePreference {
    var settingsFooter: String {
        switch self {
        case .system:
            "On-device Apple SpeechAnalyzer. Shared system speech models."
        case .parakeet:
            "Optional local NeMo-Speech install. Recordings are never uploaded."
        }
    }
}

private extension SystemTranscriptionStatus {
    var settingsFooter: String {
        switch self {
        case .ready(let locale):
            "\(locale) · on-device"
        case .needsDownload(let locale):
            "Download the Apple speech model for \(locale). Analysis still works without it."
        case .downloading(let locale):
            "Downloading model for \(locale)…"
        case .unavailable(let message):
            message
        }
    }
}

private extension TranscriptionSetupStatus {
    var settingsFooter: String {
        switch self {
        case .ready(_, let modelID):
            "\(modelID) · local only"
        case .missing:
            "Optional. System transcription works without Parakeet."
        case .installing(let phase):
            phase.userFacingLabel
        case .failed(let message), .unsupported(let message):
            message
        }
    }
}
