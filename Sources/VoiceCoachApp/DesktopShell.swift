import SwiftUI
import VoiceCoachCore

struct SnapshotSourceListSidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: 8)
            snapshotRow("Home", symbol: "waveform", selected: model.destination.navigationSection == .home)
            snapshotRow("Library", symbol: "rectangle.stack", selected: model.destination.navigationSection == .library)
            snapshotRow("Mimics", symbol: "waveform.path", selected: model.destination.navigationSection == .mimics)
            Text("RECENTS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Studio.secondary)
                .padding(.top, 18)
                .padding(.horizontal, 10)
            ForEach(model.libraryRecordings.prefix(7)) { recording in
                snapshotRow(
                    recording.displayTitle,
                    symbol: recording.isMimicAttempt ? "waveform.path" : recording.take.takeSource.icon,
                    selected: model.selectedTakeID == recording.id
                )
            }
            Spacer()
            Label("On-device", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(Studio.secondary)
                .padding(10)
        }
        .padding(8)
        .background(Studio.sidebar)
    }

    private func snapshotRow(_ title: String, symbol: String, selected: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(.callout)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(selected ? Studio.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct SourceListSidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(NavigationSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(SidebarSelection.section(section))
                }
            }

            Section("Recents") {
                let recents = Array(model.libraryRecordings.prefix(7))
                if recents.isEmpty {
                    Text("No recordings yet")
                        .foregroundStyle(Studio.secondary)
                        .font(.callout)
                } else {
                    ForEach(recents) { recording in
                        HStack(spacing: 8) {
                            Image(systemName: recording.isMimicAttempt ? "waveform.path" : recording.take.takeSource.icon)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recording.displayTitle)
                                    .lineLimit(1)
                                Text(recording.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .tag(SidebarSelection.recording(recording.id))
                        .accessibilityLabel(recording.accessibilityLabel)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .disabled(model.isRecording)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Label("On-device", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Voice Coach Settings")
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }

    private var selection: Binding<SidebarSelection?> {
        Binding(
            get: {
                switch model.destination {
                case .practice:
                    return .section(.mimics)
                case .take(_, let takeID):
                    return .recording(takeID)
                case .home, .mimicStart, .library, .mimics:
                    return .section(model.destination.navigationSection)
                }
            },
            set: { selection in
                guard !model.isRecording, let selection else { return }
                Task { @MainActor in
                    switch selection {
                    case .section(let section): model.navigate(toSection: section)
                    case .recording(let takeID):
                        if let recording = RecordingCatalog.recording(takeID: takeID, in: model.sessions) {
                            model.openTake(sessionID: recording.sessionID, takeID: takeID)
                        }
                    }
                }
            }
        )
    }
}

private enum SidebarSelection: Hashable {
    case section(NavigationSection)
    case recording(UUID)
}

struct DesktopLibraryWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("voiceCoach.hideTranscriptSnippets") private var hideTranscriptSnippets = false
    @State private var search = ""
    @State private var filter: LibraryFilter = .all
    @State private var deleteRecording: LibraryRecording?
    @State private var renameSession: CoachingSession?
    @State private var renameText = ""

    private var filtered: [LibraryRecording] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.libraryRecordings.filter { recording in
            guard filter.matches(recording) else { return false }
            return recording.matches(query: query)
        }
    }

    var body: some View {
        StudioPage(maxWidth: 1100, horizontalPadding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("\(model.userRecordedTakeCount) you recorded · \(model.importedTakeCount) imported · \(vcNumber(model.userRecordedDuration / 60, 1)) min")
                        .font(.caption)
                        .foregroundStyle(Studio.secondary)
                    Spacer()
                    if snapshot {
                        Text(filter.title)
                            .font(.caption)
                            .foregroundStyle(Studio.secondary)
                    } else {
                        Picker("Filter", selection: $filter) {
                            ForEach(LibraryFilter.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                        .labelsHidden()
                    }
                }

                if filtered.isEmpty {
                    emptyLibrary
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("RECORDING").frame(maxWidth: .infinity, alignment: .leading)
                            Text("DURATION").frame(width: 90, alignment: .trailing)
                            Text("DATE").frame(width: 120, alignment: .trailing)
                            Color.clear.frame(width: 28)
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Studio.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 32)

                        Divider()

                        ForEach(filtered) { recording in
                            recordingRow(recording)
                            if recording.id != filtered.last?.id { Divider().padding(.leading, 48) }
                        }
                    }
                    .desktopPanel()
                }
            }
        }
        .modifier(OptionalSearchable(text: $search, enabled: !snapshot, prompt: "Search recordings, prompts, transcripts"))
        .alert("Delete recording?", isPresented: deleteAlertBinding, presenting: deleteRecording) { recording in
            Button("Delete", role: .destructive) {
                model.selectedSessionID = recording.sessionID
                model.deleteTake(recording.take.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { recording in
            Text("“\(recording.displayTitle)” will be removed. Other takes and Mimic references stay.")
        }
        .alert("Rename", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameSession = nil }
            Button("Rename") {
                if let renameSession {
                    model.renameSession(renameSession.id, to: renameText)
                }
                renameSession = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func recordingRow(_ recording: LibraryRecording) -> some View {
        HStack(spacing: 10) {
            Button { model.openTake(sessionID: recording.sessionID, takeID: recording.take.id) } label: {
                HStack(spacing: 10) {
                    Image(systemName: recording.isMimicAttempt ? "waveform.path" : recording.take.takeSource.icon)
                        .foregroundStyle(Studio.accent)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.displayTitle)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(rowDetail(recording))
                            .font(.caption)
                            .foregroundStyle(Studio.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recording.accessibilityLabel)

            Text(vcDuration(recording.take.result.metrics.duration))
                .frame(width: 90, alignment: .trailing)
            Text(recording.take.createdAt.formatted(date: .abbreviated, time: .omitted))
                .frame(width: 120, alignment: .trailing)

            if snapshot {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 24)
            } else {
                Menu {
                    Button("Open", systemImage: "arrow.right") {
                        model.openTake(sessionID: recording.sessionID, takeID: recording.take.id)
                    }
                    if let session = model.sessions.first(where: { $0.id == recording.sessionID }) {
                        Button("Rename…", systemImage: "pencil") {
                            renameText = session.name
                            renameSession = session
                        }
                    }
                    if recording.isImported {
                        Button("Use as Mimic reference", systemImage: "waveform.path") {
                            model.openTake(sessionID: recording.sessionID, takeID: recording.take.id)
                            model.useCurrentRecordingAsMimicReference()
                        }
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        if confirmBeforeDelete { deleteRecording = recording }
                        else {
                            model.selectedSessionID = recording.sessionID
                            model.deleteTake(recording.take.id)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(model.selectedTakeID == recording.id ? Studio.accent.opacity(0.06) : Color.clear)
    }

    private func rowDetail(_ recording: LibraryRecording) -> String {
        if hideTranscriptSnippets { return recording.subtitle }
        if let text = recording.take.transcription?.text, !text.isEmpty {
            return text.split(separator: " ").prefix(14).joined(separator: " ")
        }
        return recording.subtitle
    }

    @ViewBuilder
    private var emptyLibrary: some View {
        if search.isEmpty && filter == .all {
            ContentUnavailableView {
                Label("No recordings", systemImage: "tray")
            } description: {
                Text("Record or import from Home. Nothing is created until audio is saved.")
            } actions: {
                Button("Record") { model.startHomeRecording() }
                    .studioGlassButton(prominent: true)
            }
            .frame(maxWidth: .infinity, minHeight: 420)
            .desktopPanel()
        } else {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("Try a different search or filter.")
            )
            .frame(maxWidth: .infinity, minHeight: 420)
            .desktopPanel()
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { deleteRecording != nil }, set: { if !$0 { deleteRecording = nil } })
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(get: { renameSession != nil }, set: { if !$0 { renameSession = nil } })
    }
}

struct DesktopMimicsWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmBeforeDelete = true
    @State private var deleteCandidate: CoachingSession?

    var body: some View {
        StudioPage(maxWidth: 1100, horizontalPadding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(model.mimicSessions.count) Mimics")
                        .font(.caption)
                        .foregroundStyle(Studio.secondary)
                    Spacer()
                    Button("New Mimic", action: model.startMimic)
                        .studioGlassButton(prominent: true)
                        .disabled(model.isRecording || model.isAnalyzing)
                }

                if model.mimicSessions.isEmpty {
                    ContentUnavailableView {
                        Label("No Mimics", systemImage: "waveform.path")
                    } description: {
                        Text("Import a short clip and practice against it. Your attempts stay with that reference.")
                    } actions: {
                        Button("Start Mimic", action: model.startMimic)
                            .studioGlassButton(prominent: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 420)
                    .desktopPanel()
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.mimicSessions) { session in
                            mimicRow(session)
                            if session.id != model.mimicSessions.last?.id {
                                Divider().padding(.leading, 48)
                            }
                        }
                    }
                    .desktopPanel()
                }

                if !model.archivedMimicSessions.isEmpty {
                    SectionEyebrow(text: "Archived")
                    VStack(spacing: 0) {
                        ForEach(model.archivedMimicSessions) { session in
                            mimicRow(session, archived: true)
                        }
                    }
                    .desktopPanel()
                }
            }
        }
        .alert("Delete Mimic?", isPresented: deleteAlertBinding, presenting: deleteCandidate) { session in
            Button("Delete", role: .destructive) { model.deleteSession(session.id) }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            let attempts = session.takeCount
            Text("This removes the reference “\(session.mimicReference?.sourceName ?? session.name)” and \(attempts) \(attempts == 1 ? "attempt" : "attempts").")
        }
    }

    private func mimicRow(_ session: CoachingSession, archived: Bool = false) -> some View {
        HStack(spacing: 10) {
            Button { model.resumeSession(session.id) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(Studio.accent)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.mimicReference?.sourceName ?? session.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text("\(session.takeCount) \(session.takeCount == 1 ? "attempt" : "attempts")")
                            .font(.caption)
                            .foregroundStyle(Studio.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(session.updatedAt.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(Studio.secondary)

            if snapshot {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 24)
            } else {
                Menu {
                    Button("Open", systemImage: "arrow.right") { model.resumeSession(session.id) }
                    if archived {
                        Button("Restore", systemImage: "tray.and.arrow.up") { model.archiveMimic(session.id, archived: false) }
                    } else {
                        Button("Archive", systemImage: "archivebox") { model.archiveMimic(session.id) }
                    }
                    Divider()
                    Button("Delete…", systemImage: "trash", role: .destructive) {
                        if confirmBeforeDelete { deleteCandidate = session }
                        else { model.deleteSession(session.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
    }
}

private struct OptionalSearchable: ViewModifier {
    @Binding var text: String
    var enabled: Bool
    var prompt: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, prompt: prompt)
        } else {
            content
        }
    }
}

struct InspectorMetricCard: View {
    let title: String
    let value: String
    let unit: String
    var detail: String? = nil
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(Studio.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Studio.secondary)
            }
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Studio.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.smooth(duration: 0.22), value: value)
    }
}

struct TakeInspector: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmBeforeDelete = true
    @State private var takePendingDelete: UUID?

    var body: some View {
        StudioScroll {
            if let session = model.selectedSession, let take = model.selectedTake {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        SectionEyebrow(text: "Take")
                        Text("Take \(takeNumber(take, in: session))")
                            .font(.headline)
                        Text("\(session.name) · \(take.createdAt.formatted(date: .omitted, time: .shortened)) · \(vcNumber(take.result.metrics.duration, 1))s")
                            .font(.caption)
                            .foregroundStyle(Studio.secondary)
                            .lineLimit(2)
                        if model.isSuggestingTitle {
                            Text("Naming from transcript…")
                                .font(.caption2)
                                .foregroundStyle(Studio.secondary.opacity(0.85))
                        }
                    }

                    Divider()

                    if !session.prompt.isEmpty {
                        SectionEyebrow(text: "Prompt")
                        Text(session.prompt)
                            .font(.callout)
                            .foregroundStyle(Studio.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()
                    }

                    InspectorMetricCard(title: "Pitch Dynamic Range", value: vcOptional(take.result.metrics.pitchRangeSemitones), unit: "st", symbol: "waveform.path")
                    InspectorMetricCard(title: "Trailing Energy Drop", value: vcSigned(take.result.metrics.phraseDecayDB), unit: "dB", symbol: "arrow.down.right")
                    InspectorMetricCard(title: "Vocal Clarity (HNR)", value: vcOptional(take.result.metrics.hnrDB), unit: "dB", symbol: "sparkles")
                    InspectorMetricCard(
                        title: "Pause Cadence",
                        value: "\(take.result.metrics.internalPauseCount)",
                        unit: take.result.metrics.internalPauseCount == 1 ? "pause" : "pauses",
                        detail: "\(vcNumber(take.result.metrics.meanInternalPauseMs, 0)) ms average",
                        symbol: "pause.fill"
                    )

                    Divider()

                    VStack(spacing: 8) {
                        Button(action: model.copyAICoachPrompt) {
                            Label("Copy Coach Prompt", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .help("Copy a prompt with this take’s measurements for an AI coach")

                        Button(action: model.exportCurrent) {
                            Label("Export Audio + JSON", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .help("Export the recording and analysis files")

                        HStack(spacing: 8) {
                            Menu {
                                Button("Copy Raw JSON", systemImage: "curlybraces", action: model.copyReport)
                            } label: {
                                Label("More", systemImage: "ellipsis")
                                    .frame(maxWidth: .infinity)
                            }
                            .menuStyle(.button)
                            .buttonStyle(.bordered)

                            Button(action: { requestDelete(take.id) }) {
                                Label("Delete", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(model.isPlaying || model.isAnalyzing)
                            .help("Delete this take")
                        }
                    }
                }
                .padding(16)
                .modifier(DeleteTakeDialog(takeID: $takePendingDelete) { takeID in
                    model.deleteTake(takeID)
                })
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func takeNumber(_ take: PracticeSession, in session: CoachingSession) -> Int {
        (session.takes.firstIndex(where: { $0.id == take.id }) ?? 0) + 1
    }

    private func requestDelete(_ takeID: UUID) {
        if confirmBeforeDelete { takePendingDelete = takeID }
        else { model.deleteTake(takeID) }
    }
}
