import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

struct DesktopMimicsWorkspace: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot
  @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmBeforeDelete = true
  @State private var deleteCandidate: CoachingSession?

  var body: some View {
    StudioPage(maxWidth: 1100, horizontalPadding: 20) {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text("\(model.mimicSessions.count) Mimics")
            .font(.caption)
            .foregroundStyle(Studio.secondary)
          Spacer()
          Button("New Mimic", action: model.startMimic)
            .studioGlassButton(prominent: true)
            .disabled(model.isRecording || model.isAnalyzing)
        }

        if model.mimicSessions.isEmpty {
          ContentUnavailableView {
            Label("No Mimics", systemImage: "waveform.path")
          } description: {
            Text(
              "Import a clip and practice against it."
            )
          } actions: {
            Button("New Mimic", action: model.startMimic)
              .studioGlassButton(prominent: true)
          }
          .frame(maxWidth: .infinity, minHeight: 420)
          .desktopPanel()
        } else {
          VStack(spacing: 0) {
            ForEach(model.mimicSessions) { session in
              mimicRow(session)
              if session.id != model.mimicSessions.last?.id {
                Divider().padding(.leading, 48)
              }
            }
          }
          .desktopPanel()
        }

        if !model.archivedMimicSessions.isEmpty {
          SectionEyebrow(text: "Archived")
          VStack(spacing: 0) {
            ForEach(model.archivedMimicSessions) { session in
              mimicRow(session, archived: true)
            }
          }
          .desktopPanel()
        }
      }
    }
    .alert("Delete Mimic?", isPresented: deleteAlertBinding, presenting: deleteCandidate) {
      session in
      Button("Delete", role: .destructive) { model.deleteSession(session.id) }
      Button("Cancel", role: .cancel) {}
    } message: { session in
      let attempts = session.takeCount
      Text(
        "This deletes “\(session.mimicReference?.sourceName ?? session.name)” and \(attempts) \(attempts == 1 ? "attempt" : "attempts")."
      )
    }
  }

  private func mimicRow(_ session: CoachingSession, archived: Bool = false) -> some View {
    HStack(spacing: 10) {
      Button {
        model.resumeSession(session.id)
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "waveform.path")
            .foregroundStyle(Studio.accent)
            .frame(width: 26)
          VStack(alignment: .leading, spacing: 2) {
            Text(session.mimicReference?.sourceName ?? session.name)
              .font(.body.weight(.medium))
              .lineLimit(1)
            Text("\(session.takeCount) \(session.takeCount == 1 ? "attempt" : "attempts")")
              .font(.caption)
              .foregroundStyle(Studio.secondary)
          }
          Spacer()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Text(session.updatedAt.formatted(.relative(presentation: .named)))
        .font(.caption)
        .foregroundStyle(Studio.secondary)

      if snapshot {
        Image(systemName: "ellipsis")
          .frame(width: 28, height: 24)
      } else {
        Menu {
          Button("Open", systemImage: "arrow.right") { model.resumeSession(session.id) }
          if archived {
            Button("Restore", systemImage: "tray.and.arrow.up") {
              model.archiveMimic(session.id, archived: false)
            }
          } else {
            Button("Archive", systemImage: "archivebox") { model.archiveMimic(session.id) }
          }
          Divider()
          Button("Delete…", systemImage: "trash", role: .destructive) {
            if confirmBeforeDelete {
              deleteCandidate = session
            } else {
              model.deleteSession(session.id)
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
    .padding(.horizontal, 12)
    .frame(height: 54)
  }

  private var deleteAlertBinding: Binding<Bool> {
    Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
  }
}
