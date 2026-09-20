import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

struct SnapshotSourceListSidebar: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Color.clear.frame(height: 8)
      snapshotRow(
        "Home", symbol: "waveform", selected: model.destination.navigationSection == .home)
      snapshotRow(
        "Library", symbol: "rectangle.stack",
        selected: model.destination.navigationSection == .library)
      snapshotRow(
        "Mimics", symbol: "waveform.path", selected: model.destination.navigationSection == .mimics)
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
      .background(
        selected ? Studio.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
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
              Image(
                systemName: recording.isMimicAttempt
                  ? "waveform.path" : recording.take.takeSource.icon
              )
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
        .help("Settings")
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
