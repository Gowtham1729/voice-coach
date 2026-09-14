import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @State private var inspectorPresented = true

    var body: some View {
        shell
            .foregroundStyle(Studio.ink)
            .preferredColorScheme(.dark)
            .tint(Studio.accent)
            .alert("Voice Coach", isPresented: errorBinding) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .overlay(alignment: .bottom) { toast }
            .onChange(of: model.destination) { _, _ in
                inspectorPresented = inspectorEligible
            }
    }

    @ViewBuilder
    private var shell: some View {
        if snapshot {
            snapshotShell
        } else {
            liveShell
        }
    }

    private var liveShell: some View {
        NavigationStack {
            HStack(spacing: 0) {
                SourceListSidebar()
                    .frame(width: 240)
                    .frame(maxHeight: .infinity)
                Divider()
                destination
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Studio.background)
            }
            .navigationTitle(workspaceTitle)
        }
        .inspector(isPresented: inspectorBinding) {
            contextualInspector
                .inspectorColumnWidth(min: 270, ideal: 300, max: 340)
        }
        .toolbar { workspaceToolbar }
    }

    private var snapshotShell: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(workspaceTitle).font(.headline)
                Spacer()
                if showsNewSessionButton {
                    Label("New Session", systemImage: "plus")
                }
                if inspectorEligible {
                    Label("Inspector", systemImage: "sidebar.right")
                }
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Studio.sidebar)

            HStack(spacing: 0) {
                SnapshotSourceListSidebar()
                    .frame(width: 240)
                Rectangle().fill(Studio.line).frame(width: 1)
                destination
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Studio.background)
                if inspectorEligible {
                    Rectangle().fill(Studio.line).frame(width: 1)
                    contextualInspector.frame(width: 300)
                }
            }
        }
        .background(Studio.background)
    }

    @ViewBuilder
    private var destination: some View {
        switch model.destination {
        case .studio:
            DesktopStudioWorkspace()
        case .create:
            CreateSessionView()
        case .practice:
            PracticeView()
        case .take:
            TakeView()
        case .sessions:
            DesktopSessionsWorkspace()
        case .insights:
            InsightsView()
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var contextualInspector: some View {
        if model.destination.isTake {
            TakeInspector()
        } else {
            SessionInspector()
        }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        if model.destination.isTake, let session = model.selectedSession {
            ToolbarItem(placement: .navigation) {
                Button { model.resumeSession(session.id) } label: {
                    Label("Back to Session", systemImage: "chevron.left")
                }
                .help("Return to the session")
            }
        } else if model.destination == .create {
            ToolbarItem(placement: .navigation) {
                Button { model.navigate(to: AppDestination.studio) } label: {
                    Label("Back to Studio", systemImage: "chevron.left")
                }
            }
        }

        if showsNewSessionButton {
            ToolbarItem(placement: .primaryAction) {
                Button { model.navigate(to: AppDestination.create) } label: {
                    Label("New Session", systemImage: "plus")
                }
                .help("Create a named practice session")
                .disabled(model.isRecording || model.isAnalyzing || model.isRequestingPermission)
            }
        }

        if inspectorEligible {
            ToolbarItem(placement: .primaryAction) {
                Button { inspectorPresented.toggle() } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help(inspectorPresented ? "Hide Inspector" : "Show Inspector")
            }
        }
    }

    private var workspaceTitle: String {
        switch model.destination {
        case .studio: model.selectedSession?.name ?? "Studio"
        case .create: "New Session"
        case .practice: model.selectedSession?.name ?? "Practice"
        case .take: takeTitle
        case .sessions: "All Sessions"
        case .insights: "Insights"
        case .settings: "Settings"
        }
    }

    private var showsNewSessionButton: Bool {
        switch model.destination {
        case .studio, .practice, .sessions: true
        case .create, .take, .insights, .settings: false
        }
    }

    private var inspectorEligible: Bool {
        switch model.destination {
        case .studio, .practice:
            model.selectedSession != nil
        case .take:
            model.selectedTake != nil
        case .create, .sessions, .insights, .settings:
            false
        }
    }

    private var takeTitle: String {
        guard let session = model.selectedSession,
              let take = model.selectedTake,
              let index = session.takes.firstIndex(where: { $0.id == take.id })
        else { return "Take" }
        return "Take \(index + 1)"
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { inspectorPresented && inspectorEligible },
            set: { inspectorPresented = $0 }
        )
    }

    private var toast: some View {
        Group {
            if let message = model.toastMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
                    .padding(.bottom, 18)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.7))
                        if !Task.isCancelled, model.toastMessage == message { model.toastMessage = nil }
                    }
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}
