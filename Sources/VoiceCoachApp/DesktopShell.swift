import SwiftUI
import VoiceCoachCore

struct SnapshotSourceListSidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: 8)
            snapshotRow("Studio", symbol: "waveform", selected: model.destination.navigationSection == .studio)
            snapshotRow("All Sessions", symbol: "rectangle.stack", selected: model.destination.navigationSection == .sessions)
            snapshotRow("Insights", symbol: "chart.xyaxis.line", selected: model.destination.navigationSection == .insights)
            Text("RECENTS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Studio.secondary)
                .padding(.top, 18)
                .padding(.horizontal, 10)
            ForEach(model.sessions.prefix(7)) { session in
                snapshotRow(session.name, symbol: session.mode.icon, selected: model.selectedSessionID == session.id && model.destination.navigationSection == .studio)
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
                if model.sessions.isEmpty {
                    Text("No sessions yet")
                        .foregroundStyle(Studio.secondary)
                        .font(.callout)
                } else {
                    ForEach(model.sessions.prefix(7)) { session in
                        HStack(spacing: 8) {
                            Image(systemName: session.mode.icon)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name)
                                    .lineLimit(1)
                                Text(recentSubtitle(session))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .tag(SidebarSelection.session(session.id))
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
                case .practice(let sessionID), .take(let sessionID, _):
                    return .session(sessionID)
                case .studio, .create, .sessions, .insights:
                    return .section(model.destination.navigationSection)
                }
            },
            set: { selection in
                guard !model.isRecording, let selection else { return }
                Task { @MainActor in
                    switch selection {
                    case .section(let section): model.navigate(to: section)
                    case .session(let sessionID): model.resumeSession(sessionID)
                    }
                }
            }
        )
    }

    private func recentSubtitle(_ session: CoachingSession) -> String {
        "\(takeCountLabel(for: session)) · \(session.updatedAt.formatted(.relative(presentation: .named)))"
    }
}

private enum SidebarSelection: Hashable {
    case section(NavigationSection)
    case session(UUID)
}

struct DesktopStudioWorkspace: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        StudioPage(maxWidth: 1180, horizontalPadding: 20) {
            if let session = model.selectedSession {
                VStack(alignment: .leading, spacing: 14) {
                    sessionHeader(session)
                    inputMonitor(session)
                    takeList(session)
                }
            } else {
                emptyStudio
            }
        }
    }

    private func sessionHeader(_ session: CoachingSession) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Label(session.mode.title, systemImage: session.mode.icon)
                .font(.callout.weight(.medium))
            Spacer()
            Text(session.updatedAt.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(Studio.secondary)
        }
    }

    private func inputMonitor(_ session: CoachingSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label(model.isRecording ? "Recording" : "Audio Input", systemImage: model.isRecording ? "record.circle.fill" : "mic")
                    .font(.headline)
                    .foregroundStyle(model.isRecording ? Color.red : Studio.ink)

                LiveMeterView(level: model.liveLevel)
                    .frame(maxWidth: .infinity)

                Text(model.isRecording ? vcDuration(model.elapsed) : "\(Int(model.liveLevel)) dBFS")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Studio.secondary)
                    .frame(width: 78, alignment: .trailing)

                Button(action: model.importClip) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .tint(.primary)
                .studioGlassButton()
                .disabled(model.isRecording || model.isAnalyzing || model.isRequestingPermission)

                Button(action: model.recordButtonPressed) {
                    Label(recordButtonTitle(session), systemImage: model.isRecording ? "stop.fill" : "record.circle")
                }
                .tint(model.isRecording ? .red : Studio.accent)
                .studioGlassButton(prominent: true)
                .keyboardShortcut(.space, modifiers: [])
                .disabled(model.isAnalyzing || model.isRequestingPermission)
            }

            if model.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Analyzing pitch, loudness, pauses, and voice quality on this Mac…")
                        .font(.caption)
                        .foregroundStyle(Studio.secondary)
                }
            } else if !session.prompt.isEmpty {
                Text(session.prompt)
                    .font(.callout)
                    .foregroundStyle(Studio.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .desktopPanel()
    }

    private func takeList(_ session: CoachingSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionEyebrow(text: "Takes")
                Spacer()
                Text(takeCountLabel(for: session))
                    .font(.caption)
                    .foregroundStyle(Studio.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)

            Divider()

            if session.takes.isEmpty {
                ContentUnavailableView {
                    Label("No Takes Yet", systemImage: "waveform.badge.plus")
                } description: {
                    Text("Record or import a take to begin this session.")
                } actions: {
                    Button("Record a Take", action: model.recordButtonPressed)
                        .tint(.primary)
                        .studioGlassButton()
                        .disabled(model.isAnalyzing || model.isRequestingPermission)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ForEach(Array(session.takes.enumerated().reversed()), id: \.element.id) { index, take in
                    Button { model.openTake(sessionID: session.id, takeID: take.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: take.takeSource.icon)
                                .foregroundStyle(Studio.accent)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Take \(index + 1)")
                                    .font(.body.weight(.medium))
                                Text(take.takeSource.title)
                                    .font(.caption)
                                    .foregroundStyle(Studio.secondary)
                            }

                            Spacer()

                            Text(take.createdAt.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(Studio.secondary)
                                .frame(width: 90, alignment: .trailing)
                            Text(vcDuration(take.result.metrics.duration))
                                .monospacedDigit()
                                .frame(width: 62, alignment: .trailing)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Studio.secondary)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .studioHoverLift()

                    if take.id != session.takes.first?.id {
                        Divider().padding(.leading, 48)
                    }
                }
            }
        }
        .desktopPanel()
    }

    private var emptyStudio: some View {
        ContentUnavailableView {
            Label("Voice Coach Studio", systemImage: "waveform")
        } description: {
            Text("Create a session or start a quick recording.")
        } actions: {
            Button("Quick Record", action: model.startQuickPractice)
                .studioGlassButton(prominent: true)
            Button("New Session") { model.navigate(to: .create) }
                .tint(.primary)
                .studioGlassButton()
        }
        .frame(maxWidth: .infinity, minHeight: 460)
    }

    private func recordButtonTitle(_ session: CoachingSession) -> String {
        if model.isRecording { return "Stop" }
        if model.isAnalyzing { return "Analyzing…" }
        return session.takes.isEmpty ? "Record" : "New Take"
    }

}

struct DesktopSessionsWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmBeforeDelete = true
    @State private var search = ""
    @State private var deleteCandidate: CoachingSession?
    @State private var renameCandidate: CoachingSession?
    @State private var renameText = ""

    private var filteredSessions: [CoachingSession] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.sessions }
        return model.sessions.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.prompt.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        StudioPage(maxWidth: 1100, horizontalPadding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("\(model.sessions.count) sessions · \(model.totalTakeCount) takes")
                        .font(.caption)
                        .foregroundStyle(Studio.secondary)
                    Spacer()
                }

                if filteredSessions.isEmpty {
                    emptySessionsView
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("SESSION").frame(maxWidth: .infinity, alignment: .leading)
                            Text("TAKES").frame(width: 70, alignment: .trailing)
                            Text("DURATION").frame(width: 90, alignment: .trailing)
                            Text("UPDATED").frame(width: 120, alignment: .trailing)
                            Color.clear.frame(width: 28)
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Studio.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 32)

                        Divider()

                        ForEach(filteredSessions) { session in
                            sessionRow(session)
                            if session.id != filteredSessions.last?.id { Divider().padding(.leading, 48) }
                        }
                    }
                    .desktopPanel()
                }
            }
        }
        .searchable(text: $search, prompt: "Search Sessions")
        .alert("Delete session?", isPresented: deleteAlertBinding, presenting: deleteCandidate) { session in
            Button("Delete", role: .destructive) { model.deleteSession(session.id) }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text("“\(session.name)” and its local recordings will be removed.")
        }
        .alert("Rename Session", isPresented: renameAlertBinding) {
            TextField("Session name", text: $renameText)
            Button("Cancel", role: .cancel) { renameCandidate = nil }
            Button("Rename") {
                if let renameCandidate {
                    model.renameSession(renameCandidate.id, to: renameText)
                }
                renameCandidate = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Choose a name that will be easy to find in your practice library.")
        }
    }

    private func sessionRow(_ session: CoachingSession) -> some View {
        HStack(spacing: 10) {
            Button { model.resumeSession(session.id) } label: {
                HStack(spacing: 10) {
                    Image(systemName: session.mode.icon)
                        .foregroundStyle(Studio.accent)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(session.prompt.isEmpty ? session.mode.title : session.prompt)
                            .font(.caption)
                            .foregroundStyle(Studio.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("\(session.takeCount)")
                .frame(width: 70, alignment: .trailing)
            Text(vcDuration(session.totalDuration))
                .frame(width: 90, alignment: .trailing)
            Text(session.updatedAt.formatted(date: .abbreviated, time: .omitted))
                .frame(width: 120, alignment: .trailing)

            if snapshot {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 24)
            } else {
                Menu {
                    Button("Open", systemImage: "arrow.right") { model.resumeSession(session.id) }
                    if session.latestTake != nil {
                        Button("Open Latest Take", systemImage: "waveform.and.mic") { model.openTake(sessionID: session.id) }
                    }
                    Button("Rename…", systemImage: "pencil") { requestRename(session) }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) {
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
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(model.selectedSessionID == session.id ? Studio.accent.opacity(0.06) : Color.clear)
    }

    @ViewBuilder
    private var emptySessionsView: some View {
        if search.isEmpty {
            ContentUnavailableView {
                Label("No Sessions", systemImage: "tray")
            } description: {
                Text("Create a session to start practicing.")
            } actions: {
                Button("New Session") { model.navigate(to: .create) }
                    .studioGlassButton(prominent: true)
            }
            .frame(maxWidth: .infinity, minHeight: 420)
            .desktopPanel()
        } else {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("Try a different search.")
            )
            .frame(maxWidth: .infinity, minHeight: 420)
            .desktopPanel()
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        )
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameCandidate != nil },
            set: { if !$0 { renameCandidate = nil } }
        )
    }

    private func requestRename(_ session: CoachingSession) {
        renameText = session.name
        renameCandidate = session
    }
}

private func takeCountLabel(for session: CoachingSession) -> String {
    let noun = session.takeCount == 1 ? "take" : "takes"
    return "\(session.takeCount) \(noun)"
}

struct SessionInspector: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        StudioScroll {
            if let session = model.selectedSession {
                VStack(alignment: .leading, spacing: 14) {
                    inspectorHeader(
                        eyebrow: "Session",
                        title: session.name,
                        detail: "Created \(session.createdAt.formatted(date: .abbreviated, time: .shortened))"
                    )

                    Divider()

                    sessionDetail("Mode", value: session.mode.title)
                    sessionDetail("Recorded", value: vcDuration(session.totalDuration))
                    sessionDetail("Updated", value: session.updatedAt.formatted(.relative(presentation: .named)))

                    if !session.prompt.isEmpty {
                        Divider()
                        SectionEyebrow(text: "Prompt")
                        Text(session.prompt)
                            .font(.callout)
                            .foregroundStyle(Studio.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                }
                .padding(16)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func sessionDetail(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Studio.secondary)
            Spacer()
            Text(value)
                .font(.callout)
                .multilineTextAlignment(.trailing)
        }
    }

    private func inspectorHeader(eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionEyebrow(text: eyebrow)
            Text(title)
                .font(.headline)
                .lineLimit(2)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Studio.secondary)
        }
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
                    }

                    Divider()

                    telemetryCard(title: "Pitch Dynamic Range", value: vcOptional(take.result.metrics.pitchRangeSemitones), unit: "st", symbol: "waveform.path")
                    telemetryCard(title: "Trailing Energy Drop", value: vcSigned(take.result.metrics.phraseDecayDB), unit: "dB", symbol: "arrow.down.right")
                    telemetryCard(title: "Vocal Clarity (HNR)", value: vcOptional(take.result.metrics.hnrDB), unit: "dB", symbol: "sparkles")
                    telemetryCard(
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

    private func telemetryCard(title: String, value: String, unit: String, detail: String? = nil, symbol: String) -> some View {
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
