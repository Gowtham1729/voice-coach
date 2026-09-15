import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var inspectorPresented = true

    var body: some View {
        shell
            .foregroundStyle(Studio.ink)
            .preferredColorScheme(.dark)
            // Charts and selection washes use accent; glass secondary controls opt out via .tint(.primary).
            .tint(Studio.accent)
            .alert("Voice Coach", isPresented: errorBinding) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .overlay(alignment: .bottom) { toast }
            .onChange(of: model.destination) { _, _ in
                if inspectorEligible {
                    inspectorPresented = true
                }
            }
    }

    private var shell: some View {
        Group {
            if snapshot {
                // ImageRenderer cannot composite NavigationSplitView / inspector glass.
                // Flatten to an opaque three-column layout for docs and layout proofs only.
                snapshotShell
            } else {
                NavigationSplitView {
                    sidebarColumn
                        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
                } detail: {
                    destination
                        .id(destinationIdentity)
                        .transition(destinationTransition)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Studio.background)
                        .toolbar { workspaceToolbar }
                        .inspector(isPresented: inspectorBinding) {
                            contextualInspector
                                .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                        }
                }
                .navigationSplitViewStyle(.balanced)
                .animation(StudioMotion.page(reduceMotion: reduceMotion), value: destinationIdentity)
                .animation(StudioMotion.page(reduceMotion: reduceMotion), value: showInspector)
            }
        }
    }

    private var snapshotShell: some View {
        HStack(spacing: 0) {
            sidebarColumn
                .frame(width: 240)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Studio.sidebar)

            destination
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Studio.background)

            if showInspector {
                contextualInspector
                    .frame(width: 300)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Studio.inspector)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Studio.background)
    }

    @ViewBuilder
    private var sidebarColumn: some View {
        if snapshot {
            SnapshotSourceListSidebar()
        } else {
            SourceListSidebar()
        }
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
        if showsBackButton {
            ToolbarItem(placement: .navigation) {
                Button(action: goBack) {
                    Label(backHelp, systemImage: "chevron.left")
                }
                .help(backHelp)
            }
        }

        ToolbarSpacer(.flexible)

        if showsNewSession {
            ToolbarItem {
                Button {
                    model.navigate(to: AppDestination.create)
                } label: {
                    Label("New Session", systemImage: "plus")
                }
                .help("Create a named practice session")
                .disabled(model.isRecording || model.isAnalyzing || model.isRequestingPermission)
            }
        }

        if inspectorEligible {
            ToolbarItem {
                Button {
                    inspectorPresented.toggle()
                } label: {
                    Label(
                        inspectorPresented ? "Hide Inspector" : "Show Inspector",
                        systemImage: "sidebar.trailing"
                    )
                }
                .help(inspectorPresented ? "Hide Inspector" : "Show Inspector")
            }
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { showInspector },
            set: { newValue in
                guard inspectorEligible else { return }
                inspectorPresented = newValue
            }
        )
    }

    private var showInspector: Bool {
        inspectorPresented && inspectorEligible
    }

    private var showsNewSession: Bool {
        switch model.destination {
        case .studio, .practice, .sessions: true
        case .create, .take, .insights, .settings: false
        }
    }

    private var showsBackButton: Bool {
        switch model.destination {
        case .create, .take: true
        case .studio, .practice, .sessions, .insights, .settings: false
        }
    }

    private var backHelp: String {
        model.destination.isTake ? "Return to the session" : "Return to Studio"
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

    private var destinationIdentity: String {
        switch model.destination {
        case .studio: "studio"
        case .create: "create"
        case .practice(let id): "practice-\(id)"
        case .take(let session, let take): "take-\(session)-\(take)"
        case .sessions: "sessions"
        case .insights: "insights"
        case .settings: "settings"
        }
    }

    private var destinationTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.995)),
            removal: .opacity.combined(with: .offset(y: -4))
        )
    }

    private func goBack() {
        if model.destination.isTake, let session = model.selectedSession {
            model.resumeSession(session.id)
        } else {
            model.navigate(to: AppDestination.studio)
        }
    }

    private var toast: some View {
        Group {
            if let message = model.toastMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .modifier(ControlGlass(
                        tint: Studio.accent.opacity(0.18),
                        opaque: reduceTransparency || snapshot,
                        cornerRadius: 8
                    ))
                    .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
                    .padding(.bottom, 18)
                    .transition(toastTransition)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.7))
                        if !Task.isCancelled, model.toastMessage == message { model.toastMessage = nil }
                    }
            }
        }
        .animation(StudioMotion.spring(reduceMotion: reduceMotion), value: model.toastMessage)
    }

    private var toastTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96))
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}
