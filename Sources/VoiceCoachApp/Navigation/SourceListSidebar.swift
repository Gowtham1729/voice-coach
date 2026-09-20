import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

struct SnapshotSourceListSidebar: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Color.clear.frame(height: 8)
      snapshotRow(
        "Home", symbol: "waveform", selected: snapshotSectionSelection == .home)
      snapshotRow(
        "Library", symbol: "rectangle.stack",
        selected: snapshotSectionSelection == .library)
      snapshotRow(
        "Mimics", symbol: "waveform.path", selected: snapshotSectionSelection == .mimics)
      Text("RECENTS")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Studio.secondary)
        .padding(.top, 18)
        .padding(.horizontal, 10)
      ForEach(snapshotRecents) { recording in
        SidebarRecentsRow(recording: recording)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(
            snapshotRecordingSelection == recording.id
              ? Studio.accent.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
          )
      }
      if model.libraryRecordings.count > snapshotRecents.count {
        Text("Show all")
          .font(.caption)
          .foregroundStyle(Studio.secondary)
          .padding(.horizontal, 10)
          .padding(.top, 4)
      }
      Spacer()
      sidebarFooter
    }
    .padding(8)
    .background(Studio.sidebar)
  }

  private var snapshotSectionSelection: NavigationSection? {
    switch model.destination {
    case .take: nil
    case .practice: .mimics
    case .home, .mimicStart, .library, .mimics: model.destination.navigationSection
    }
  }

  private var snapshotRecordingSelection: UUID? {
    if case .take(_, let takeID) = model.destination { return takeID }
    return nil
  }

  private var snapshotRecents: [LibraryRecording] {
    sidebarRecents(from: model, limit: 7)
  }

  private var sidebarFooter: some View {
    VStack(spacing: 0) {
      Divider()
      if model.isRecording {
        HStack(spacing: 6) {
          Image(systemName: "record.circle.fill")
            .foregroundStyle(.red)
          Text("Recording")
            .foregroundStyle(.red)
          Spacer(minLength: 0)
          Text(vcDuration(model.elapsed))
            .font(.caption.monospacedDigit())
            .foregroundStyle(Studio.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
      }
      HStack(spacing: 8) {
        Label("On-device", systemImage: "lock.fill")
          .font(.caption)
          .foregroundStyle(Studio.secondary)
        Spacer(minLength: 0)
        Image(systemName: "gearshape")
          .font(.caption)
          .foregroundStyle(Studio.secondary)
          .accessibilityLabel("Settings")
      }
      .padding(.horizontal, 10)
      .padding(.top, model.isRecording ? 4 : 8)
      .padding(.bottom, 8)
    }
  }

  private func snapshotRow(
    _ title: String, symbol: String, selected: Bool, trailing: String? = nil
  ) -> some View {
    HStack(spacing: 8) {
      Label(title, systemImage: symbol)
        .font(.callout)
        .lineLimit(1)
      if let trailing {
        Spacer(minLength: 0)
        Text(trailing)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(Studio.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 8)
    .frame(height: 30)
    .background(
      selected ? Studio.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
  }
}

struct TakeCountChip: View {
  let takeNumber: Int
  let takeCount: Int

  var body: some View {
    Text("\(takeNumber)/\(takeCount)")
      .font(.caption2.weight(.semibold).monospacedDigit())
      .foregroundStyle(Studio.secondary)
      .padding(.horizontal, 5)
      .padding(.vertical, 1.5)
      .background(Studio.line, in: Capsule())
      .accessibilityHidden(true)
  }
}

struct SidebarRecentsRow: View {
  let recording: LibraryRecording

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: recording.iconSymbol)
        .foregroundStyle(Studio.accent)
        .frame(width: 16)
      VStack(alignment: .leading, spacing: 2) {
        Text(recording.sidebarTitle)
          .lineLimit(1)
        Text(recording.sidebarSubtitle)
          .font(.caption)
          .foregroundStyle(Studio.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      HStack(spacing: 5) {
        if recording.takeCount > 1 {
          TakeCountChip(takeNumber: recording.takeNumber, takeCount: recording.takeCount)
        }
        Text(vcDuration(recording.take.result.metrics.duration))
          .font(.caption.monospacedDigit())
          .foregroundStyle(Studio.secondary)
      }
    }
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
      .disabled(model.isRecording)

      Section {
        let recents = sidebarRecents(from: model, limit: 7)
        if recents.isEmpty {
          Text("No recordings yet")
            .foregroundStyle(Studio.secondary)
            .font(.callout)
        } else {
          ForEach(recents) { recording in
            SidebarRecentsRow(recording: recording)
              .tag(SidebarSelection.recording(recording.id))
              .accessibilityLabel(recording.accessibilityLabel)
          }

          if model.libraryRecordings.count > recents.count {
            Button("Show all") {
              model.navigate(toSection: .library)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .disabled(model.isRecording)
            .selectionDisabled()
            .accessibilityLabel("Show all recordings")
          }
        }
      } header: {
        Text("Recents")
      }
      .disabled(model.isRecording)
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 0) {
        Divider()
        if model.isRecording {
          HStack(spacing: 6) {
            Image(systemName: "record.circle.fill")
              .foregroundStyle(.red)
            Text("Recording")
              .foregroundStyle(.red)
            Spacer(minLength: 0)
            Text(vcDuration(model.elapsed))
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
          .font(.caption)
          .padding(.horizontal, 12)
          .padding(.top, 8)
          .padding(.bottom, 4)
          .accessibilityElement(children: .combine)
          .accessibilityLabel("Recording \(vcDuration(model.elapsed))")
        }
        HStack(spacing: 8) {
          Label("On-device", systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer(minLength: 0)
          SettingsLink {
            Label("Settings", systemImage: "gearshape")
              .labelStyle(.iconOnly)
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
          .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.top, model.isRecording ? 4 : 8)
        .padding(.bottom, 8)
      }
      .background(Studio.sidebar)
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
        guard let selection else { return }
        if model.isRecording { return }
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

@MainActor
private func sidebarRecents(from model: AppModel, limit: Int) -> [LibraryRecording] {
  let all = model.libraryRecordings
  var items = Array(all.prefix(limit))
  if case .take(_, let takeID) = model.destination,
    !items.contains(where: { $0.id == takeID }),
    let selected = all.first(where: { $0.id == takeID })
      ?? RecordingCatalog.recording(takeID: takeID, in: model.sessions)
  {
    items.insert(selected, at: 0)
    if items.count > limit {
      items.removeLast()
    }
  }
  return items
}
