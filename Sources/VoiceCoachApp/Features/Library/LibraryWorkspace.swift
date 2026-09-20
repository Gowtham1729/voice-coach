import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

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
          Text(
            "\(model.userRecordedTakeCount) you recorded · \(model.importedTakeCount) imported · \(vcNumber(model.userRecordedDuration / 60, 1)) min"
          )
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
    .modifier(
      OptionalSearchable(
        text: $search, enabled: !snapshot, prompt: "Search")
    )
    .alert("Delete recording?", isPresented: deleteAlertBinding, presenting: deleteRecording) {
      recording in
      Button("Delete", role: .destructive) {
        model.selectedSessionID = recording.sessionID
        model.deleteTake(recording.take.id)
      }
      Button("Cancel", role: .cancel) {}
    } message: { recording in
      Text("“\(recording.displayTitle)” will be deleted.")
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
      Button {
        model.openTake(sessionID: recording.sessionID, takeID: recording.take.id)
      } label: {
        HStack(spacing: 10) {
          Image(systemName: recording.iconSymbol)
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
            Button("Use as Mimic", systemImage: "waveform.path") {
              model.openTake(sessionID: recording.sessionID, takeID: recording.take.id)
              model.useCurrentRecordingAsMimicReference()
            }
          }
          Divider()
          Button("Delete", systemImage: "trash", role: .destructive) {
            if confirmBeforeDelete {
              deleteRecording = recording
            } else {
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
        Text("Record or import a clip.")
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
        description: Text("Try another search or filter.")
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
