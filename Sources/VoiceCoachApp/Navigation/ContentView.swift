import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @SceneStorage("voiceCoach.inspectorPresented") private var inspectorPresented = true
  @AppStorage(ExperimentalFeaturesPreference.storageKey) private var experimentsEnabled =
    ExperimentalFeaturesPreference.default
  @AppStorage(InspectorPane.storageKey) private var inspectorPane = InspectorPane.details.rawValue

  var body: some View {
    shell
      .tint(Studio.accent)
      .alert(model.errorTitle, isPresented: errorBinding) {
        Button("OK", role: .cancel) { model.clearError() }
      } message: {
        Text(model.errorMessage ?? "")
      }
      .sheet(isPresented: mimicStartBinding) {
        CreateSessionView()
          .environmentObject(model)
          .frame(width: 680, height: 640)
      }
      .alert("Keep all recordings?", isPresented: replaceOnlyBinding) {
        Button("Keep All") { model.confirmKeepAllFromNowOn() }
        Button("Replace Older", role: .destructive) { model.confirmReplaceOldest() }
        Button("Cancel", role: .cancel) { model.pendingReplaceOnly = nil }
      } message: {
        Text("This session used to keep only the newest take. Keep all recordings, or replace older ones?")
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
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
          }
          .animation(StudioMotion.quick(reduceMotion: reduceMotion), value: showInspector)
          .navigationTitle(windowTitle)
          .toolbar { workspaceToolbar }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.askInspectorNonce) { _, nonce in
          guard nonce > 0 else { return }
          inspectorPresented = true
          inspectorPane = InspectorPane.ask.rawValue
        }
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
    VStack(spacing: 0) {
      if showsAsk {
        inspectorModeSwitch
      }
      inspectorBody
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private var inspectorModeSwitch: some View {
    if snapshot {
      HStack(spacing: 0) {
        snapshotSegment("Details", selected: selectedPane == .details)
        snapshotSegment("Ask", selected: selectedPane == .ask)
      }
      .frame(width: 268)
      .background(Studio.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      .padding(.top, 12)
      .padding(.bottom, 4)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Inspector")
    } else {
      Picker("Inspector", selection: $inspectorPane) {
        Text("Details").tag(InspectorPane.details.rawValue)
        Text("Ask").tag(InspectorPane.ask.rawValue)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(width: 268)
      .padding(.top, 12)
      .padding(.bottom, 4)
      .accessibilityLabel("Inspector")
    }
  }

  private func snapshotSegment(_ title: String, selected: Bool) -> some View {
    Text(title)
      .font(.caption.weight(.semibold))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 5)
      .background(selected ? Studio.accent.opacity(0.18) : Color.clear)
  }

  @ViewBuilder
  private var inspectorBody: some View {
    if showsAsk, selectedPane == .ask, let context = chatContext {
      SessionChatInspector(conversation: model.conversation(for: context))
    } else if model.showsTakeInspector {
      TakeInspector()
    } else {
      MimicInspector()
    }
  }

  private var showsAsk: Bool { experimentsEnabled && chatContext != nil }

  private var selectedPane: InspectorPane {
    InspectorPane(rawValue: inspectorPane) ?? .details
  }

  private var chatContext: SessionChatContext? {
    guard experimentsEnabled, let session = model.selectedSession else { return nil }
    switch model.destination {
    case .take, .practice:
      return model.sessionChatContext(session: session, take: model.selectedTake)
    case .home, .mimicStart, .library, .mimics:
      return nil
    }
  }

  @ToolbarContentBuilder
  private var workspaceToolbar: some ToolbarContent {
    if showsBackButton {
      ToolbarItem(placement: .navigation) {
        Button(action: goBack) {
          Label(parentSectionTitle, systemImage: "chevron.backward")
        }
        .help("Back to \(parentSectionTitle)")
      }
    }

    ToolbarSpacer(.flexible)

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

  private var showsBackButton: Bool {
    switch model.destination {
    case .take:
      true
    case .practice:
      model.selectedSession != nil
    case .home, .mimicStart, .library, .mimics:
      false
    }
  }

  private var parentSectionTitle: String {
    parentSection?.title ?? ""
  }

  private var parentSection: NavigationSection? {
    switch model.destination {
    case .take: .library
    case .practice: .mimics
    case .home, .mimicStart, .library, .mimics: nil
    }
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
    switch model.destination {
    case .take:
      model.navigate(to: .library)
    case .practice:
      model.navigate(to: .mimics)
    case .home, .mimicStart, .library, .mimics:
      break
    }
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
          .modifier(
            ControlGlass(
              tint: Studio.accent.opacity(0.18),
              opaque: reduceTransparency || snapshot,
              cornerRadius: 8
            )
          )
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
    Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearError() } })
  }
}

enum InspectorPane: String {
  static let storageKey = "voiceCoach.inspectorPane"
  case details
  case ask
}
