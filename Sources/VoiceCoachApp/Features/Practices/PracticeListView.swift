import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

/// Middle column: every practice once, newest activity first. Selecting one opens it in the
/// detail column while the list stays put, so there is always a way back.
struct PracticeListView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot
  @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmBeforeDelete = true
  @AppStorage("voiceCoach.hideTranscriptSnippets") private var hideTranscriptSnippets = false
  @State private var search = ""
  @State private var deleteCandidate: CoachingSession?
  @State private var renameCandidate: CoachingSession?
  @State private var renameText = ""

  private var practices: [CoachingSession] {
    PracticeCatalog.practices(from: model.sessions, filter: model.listFilter, query: search)
  }

  var body: some View {
    let practices = practices
    let groups = PracticeCatalog.grouped(practices)
    return Group {
      if practices.isEmpty {
        emptyState
      } else if snapshot {
        snapshotList(groups)
      } else {
        List(selection: selection) {
          ForEach(groups, id: \.group) { entry in
            Section(entry.group.title) {
              ForEach(entry.sessions) { session in
                PracticeRow(session: session, snippet: snippet(for: session))
                  .tag(session.id)
                  .contextMenu { rowMenu(session) }
              }
            }
          }
        }
        .listStyle(.inset)
        .disabled(!model.canNavigate)
      }
    }
    .safeAreaInset(edge: .bottom) { footer }
    .navigationTitle(model.listFilter.title)
    .modifier(ListSearch(text: $search, enabled: !snapshot))
    .alert("Delete practice?", isPresented: deleteAlertBinding, presenting: deleteCandidate) {
      session in
      Button("Delete", role: .destructive) { model.deleteSession(session.id) }
      Button("Cancel", role: .cancel) {}
    } message: { session in
      Text(deleteMessage(for: session))
    }
    .alert("Rename practice", isPresented: renameAlertBinding) {
      TextField("Name", text: $renameText)
      Button("Cancel", role: .cancel) { renameCandidate = nil }
      Button("Rename") {
        if let renameCandidate { model.renameSession(renameCandidate.id, to: renameText) }
        renameCandidate = nil
      }
      .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  private var selection: Binding<UUID?> {
    Binding(
      get: { model.destination.isWorkspace ? model.selectedSessionID : nil },
      set: { id in
        guard let id, id != model.selectedSessionID || !model.destination.isWorkspace else {
          return
        }
        Task { @MainActor in model.resumeSession(id) }
      }
    )
  }

  @ViewBuilder
  private func rowMenu(_ session: CoachingSession) -> some View {
    Button("Open") { model.resumeSession(session.id) }
      .disabled(!model.canNavigate)
    Button("Rename…") {
      renameText = PracticeCatalog.title(of: session)
      renameCandidate = session
    }
    Divider()
    if session.archived {
      Button("Restore") { model.archiveSession(session.id, archived: false) }
        .disabled(!model.canModifySession(session.id))
    } else {
      Button("Archive") { model.archiveSession(session.id) }
        .disabled(!model.canModifySession(session.id))
    }
    Button("Delete practice…", role: .destructive) {
      if confirmBeforeDelete {
        deleteCandidate = session
      } else {
        model.deleteSession(session.id)
      }
    }
    .disabled(!model.canModifySession(session.id))
  }

  private func deleteMessage(for session: CoachingSession) -> String {
    let title = PracticeCatalog.title(of: session)
    let takes =
      session.takeCount == 0
      ? "" : session.takeCount == 1 ? " and its take" : " and all \(session.takeCount) takes"
    let reference = session.isMimic ? ", its reference" : ""
    return "This deletes “\(title)”\(takes)\(reference), including audio, transcripts, and analysis."
  }

  private func snippet(for session: CoachingSession) -> String? {
    guard !hideTranscriptSnippets else { return nil }
    let text = session.latestTake?.transcription?.text ?? session.mimicReference?.take.transcription?.text
    guard let text, !text.isEmpty else { return nil }
    return text.split(separator: " ").prefix(12).joined(separator: " ")
  }

  private func snapshotList(_ groups: [(group: PracticeListGroup, sessions: [CoachingSession])])
    -> some View
  {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(groups, id: \.group) { entry in
        Text(entry.group.title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(Studio.secondary)
          .padding(.horizontal, 14)
          .padding(.top, 12)
          .padding(.bottom, 4)
        ForEach(entry.sessions) { session in
          PracticeRow(session: session, snippet: snippet(for: session))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
              model.destination.isWorkspace && model.selectedSessionID == session.id
                ? Studio.accent.opacity(0.14) : Color.clear,
              in: RoundedRectangle(cornerRadius: 6)
            )
            .padding(.horizontal, 4)
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private var emptyState: some View {
    if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      ContentUnavailableView.search(text: search)
    } else {
      switch model.listFilter {
      case .all:
        ContentUnavailableView {
          Label("No practices yet", systemImage: "waveform")
        } description: {
          Text("Record, import a clip, or add a reference to start.")
        }
      case .withReference:
        ContentUnavailableView {
          Label("No practices with a reference", systemImage: "waveform.path")
        } description: {
          Text("Add a reference clip, then listen, repeat, and compare your takes.")
        } actions: {
          Button("New practice with reference…", action: model.startMimic)
            .disabled(!model.canStartQuickPractice)
        }
      case .archived:
        ContentUnavailableView(
          "Nothing archived", systemImage: "archivebox",
          description: Text("Archive a practice to hide it without deleting it."))
      }
    }
  }

  /// Totals live here, once, instead of on Home, Library and Settings.
  private var footer: some View {
    VStack(spacing: 0) {
      Divider()
      Text(
        "\(model.totalTakeCount) \(model.totalTakeCount == 1 ? "take" : "takes") · \(vcNumber(model.userRecordedDuration / 60, 1)) min recorded"
      )
      .font(.caption)
      .foregroundStyle(Studio.secondary)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
    }
  }

  private var deleteAlertBinding: Binding<Bool> {
    Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
  }

  private var renameAlertBinding: Binding<Bool> {
    Binding(get: { renameCandidate != nil }, set: { if !$0 { renameCandidate = nil } })
  }
}

struct PracticeRow: View {
  let session: CoachingSession
  let snippet: String?

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: session.isMimic ? "waveform.path" : "waveform")
        .foregroundStyle(Studio.accent)
        .frame(width: 18)
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(PracticeCatalog.title(of: session))
            .font(.body.weight(.medium))
            .lineLimit(1)
          Spacer(minLength: 4)
          Text(dateText)
            .font(.caption.monospacedDigit())
            .foregroundStyle(Studio.secondary)
        }
        Text(PracticeCatalog.detail(of: session))
          .font(.caption)
          .foregroundStyle(Studio.secondary)
          .lineLimit(1)
        if let snippet {
          Text(snippet)
            .font(.caption)
            .foregroundStyle(Studio.secondary)
            .lineLimit(1)
        }
      }
    }
    .padding(.vertical, 3)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(PracticeCatalog.title(of: session)), \(PracticeCatalog.detail(of: session)), \(dateText)")
  }

  /// Always an absolute date, so rows never mix "2 days ago" with "Sep 20".
  private var dateText: String {
    if Calendar.current.isDateInToday(session.updatedAt) {
      return session.updatedAt.formatted(date: .omitted, time: .shortened)
    }
    return session.updatedAt.formatted(.dateTime.day().month(.abbreviated))
  }
}

private struct ListSearch: ViewModifier {
  @Binding var text: String
  var enabled: Bool

  func body(content: Content) -> some View {
    if enabled {
      content.searchable(text: $text, placement: .sidebar, prompt: "Search practices")
    } else {
      content
    }
  }
}
