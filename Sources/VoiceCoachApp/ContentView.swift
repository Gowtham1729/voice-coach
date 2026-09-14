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
            .environment(\.workspaceChrome, workspaceChrome)
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

    private var shell: some View {
        HStack(spacing: 0) {
            Group {
                if snapshot {
                    SnapshotSourceListSidebar()
                } else {
                    SourceListSidebar()
                }
            }
            .frame(width: 240)

            Rectangle().fill(Studio.line).frame(width: 1)

            destination
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Studio.background)

            if showInspector {
                Rectangle().fill(Studio.line).frame(width: 1)
                contextualInspector
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
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

    private var workspaceChrome: WorkspaceChrome {
        WorkspaceChrome(
            showsNewSession: showsNewSession,
            inspectorEligible: inspectorEligible,
            inspectorPresented: showInspector,
            onNewSession: { model.navigate(to: AppDestination.create) },
            onToggleInspector: { inspectorPresented.toggle() },
            onBack: goBack
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

struct WorkspaceChrome {
    var showsNewSession = false
    var inspectorEligible = false
    var inspectorPresented = false
    var onNewSession: () -> Void = {}
    var onToggleInspector: () -> Void = {}
    var onBack: () -> Void = {}
}

private struct WorkspaceChromeKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = WorkspaceChrome()
}

extension EnvironmentValues {
    var workspaceChrome: WorkspaceChrome {
        get { self[WorkspaceChromeKey.self] }
        set { self[WorkspaceChromeKey.self] = newValue }
    }
}

struct WorkspaceChromeButtons: View {
    @Environment(\.workspaceChrome) private var chrome
    @EnvironmentObject private var model: AppModel
    var includeBack = false

    var body: some View {
        HStack(spacing: 4) {
            if includeBack {
                chromeButton(
                    systemImage: "chevron.left",
                    help: model.destination.isTake ? "Return to the session" : "Return to Studio",
                    action: chrome.onBack
                )
            }

            if chrome.showsNewSession {
                chromeButton(
                    systemImage: "plus",
                    help: "Create a named practice session",
                    disabled: model.isRecording || model.isAnalyzing || model.isRequestingPermission,
                    action: chrome.onNewSession
                )
            }

            if chrome.inspectorEligible {
                chromeButton(
                    systemImage: "sidebar.right",
                    help: chrome.inspectorPresented ? "Hide Inspector" : "Show Inspector",
                    active: chrome.inspectorPresented,
                    action: chrome.onToggleInspector
                )
            }
        }
    }

    private func chromeButton(
        systemImage: String,
        help: String,
        active: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Studio.accent : Studio.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}
