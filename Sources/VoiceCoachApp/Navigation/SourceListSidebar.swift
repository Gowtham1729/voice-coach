import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

/// Left column: which practices to list. Nothing else lives here, so every practice
/// appears in exactly one list.
struct SourceListSidebar: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot

  var body: some View {
    Group {
      if snapshot {
        VStack(alignment: .leading, spacing: 4) {
          Color.clear.frame(height: 8)
          ForEach(PracticeListFilter.allCases) { filter in
            snapshotRow(filter)
          }
          Spacer()
        }
        .padding(8)
      } else {
        List(selection: selection) {
          ForEach(PracticeListFilter.allCases) { filter in
            Label(filter.title, systemImage: filter.symbol)
              .badge(count(for: filter))
              .tag(filter)
          }
        }
        .listStyle(.sidebar)
        .disabled(!model.canNavigate)
      }
    }
    .safeAreaInset(edge: .bottom) { SidebarFooter() }
    .background(Studio.sidebar)
  }

  private func count(for filter: PracticeListFilter) -> Int {
    filter == .archived ? 0 : PracticeCatalog.practices(from: model.sessions, filter: filter).count
  }

  private var selection: Binding<PracticeListFilter?> {
    Binding(
      get: { model.listFilter },
      set: { filter in
        guard let filter, filter != model.listFilter else { return }
        Task { @MainActor in model.showList(filter) }
      }
    )
  }

  private func snapshotRow(_ filter: PracticeListFilter) -> some View {
    HStack(spacing: 8) {
      Label(filter.title, systemImage: filter.symbol)
        .font(.callout)
        .lineLimit(1)
      Spacer(minLength: 0)
      if count(for: filter) > 0 {
        Text("\(count(for: filter))")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(Studio.secondary)
      }
    }
    .padding(.horizontal, 8)
    .frame(height: 30)
    .background(
      model.listFilter == filter ? Studio.accent.opacity(0.14) : Color.clear,
      in: RoundedRectangle(cornerRadius: 6))
  }
}

private struct SidebarFooter: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
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
        .help("Settings")
      }
      .padding(.horizontal, 12)
      .padding(.top, model.isRecording ? 4 : 8)
      .padding(.bottom, 8)
    }
    .background(Studio.sidebar)
  }
}
