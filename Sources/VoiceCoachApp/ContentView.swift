import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @SceneStorage("voiceCoach.inspectorPresented") private var inspectorPresented = true

    var body: some View {
        shell
            .tint(Studio.accent)
            .alert("Voice Coach", isPresented: errorBinding) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .sheet(isPresented: mimicStartBinding) {
                CreateSessionView()
                    .environmentObject(model)
                    .frame(width: 680, height: 640)
            }
            .alert("Keep every recording?", isPresented: replaceOnlyBinding) {
                Button("Keep all from now on") { model.confirmKeepAllFromNowOn() }
                Button("Replace older recordings", role: .destructive) { model.confirmReplaceOldest() }
                Button("Cancel", role: .cancel) { model.pendingReplaceOnly = nil }
            } message: {
                Text("This older folder was set to keep only the newest recording. Voice Coach now keeps every valid recording unless you choose to replace.")
            }
            .overlay(alignment: .bottom) { toast }
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
                    HStack(spacing: 0) {
                        destination
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if showInspector {
                            Divider()
                            contextualInspector
                                .frame(width: 300)
                                .background(Studio.inspector)
                        }
                    }
                    .navigationTitle(windowTitle)
                    .toolbar { workspaceToolbar }
                }
                .navigationSplitViewStyle(.balanced)
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
        case .home, .mimicStart:
            HomeView()
        case .practice:
            MimicWorkspace()
        case .take:
            TakeView()
        case .library:
            DesktopLibraryWorkspace()
        case .mimics:
            DesktopMimicsWorkspace()
        }
    }

    @ViewBuilder
    private var contextualInspector: some View {
        if model.showsTakeInspector {
            TakeInspector()
        } else {
            MimicInspector()
        }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        if showsBackButton {
            ToolbarItem(placement: .navigation) {
                Button(action: goBack) {
                    Label("Return to Library", systemImage: "chevron.left")
                }
                .help("Return to Library")
            }
        }

        ToolbarSpacer(.flexible)

        if showsNewRecording {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.startHomeRecording()
                } label: {
                    Label("Record", systemImage: "plus")
                }
                .help("Record a new take on this Mac")
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

    private var showInspector: Bool {
        inspectorPresented && inspectorEligible
    }

    private var showsNewRecording: Bool {
        switch model.destination {
        case .home, .library, .mimics: true
        case .practice, .mimicStart, .take: false
        }
    }

    private var showsBackButton: Bool {
        if case .take = model.destination { return true }
        return false
    }

    private var inspectorEligible: Bool {
        switch model.destination {
        case .practice:
            model.selectedSession != nil
        case .take:
            model.selectedTake != nil
        case .home, .mimicStart, .library, .mimics:
            false
        }
    }

    private var windowTitle: String {
        switch model.destination {
        case .home: "Home"
        case .mimicStart: "Mimic"
        case .practice:
            model.selectedSession?.mimicReference?.sourceName
                ?? model.selectedSession?.name
                ?? "Mimic"
        case .take: model.selectedSession?.name ?? "Recording"
        case .library: "Library"
        case .mimics: "Mimics"
        }
    }

    private func goBack() {
        model.navigate(to: .library)
    }

    private var mimicStartBinding: Binding<Bool> {
        Binding(
            get: {
                if case .mimicStart = model.destination { return true }
                return false
            },
            set: { isPresented in
                if !isPresented, case .mimicStart = model.destination {
                    model.cancelMimicPreparation()
                    model.navigate(to: .home)
                }
            }
        )
    }

    private var replaceOnlyBinding: Binding<Bool> {
        Binding(
            get: { model.pendingReplaceOnly != nil },
            set: { if !$0 { model.pendingReplaceOnly = nil } }
        )
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
