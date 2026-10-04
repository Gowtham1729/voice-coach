import SwiftUI
import VoiceCoachSession

struct HomeView: View {
  @EnvironmentObject private var model: AppModel
  @AppStorage("voiceCoach.hideTranscriptSnippets") private var hideTranscriptSnippets = false

  var body: some View {
    StudioPage(maxWidth: 1100, horizontalPadding: 20) {
      VStack(alignment: .leading, spacing: 16) {
        welcome
        captureBar
        activityRow
        if let mimic = model.continueMimic {
          continueMimicCard(mimic)
        }
        recentRecordings
      }
    }
  }

  private var welcome: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 5) {
        SectionEyebrow(text: "Ichido")
        Text("Your private speaking room.")
          .font(.title2.weight(.semibold))
        Text("Record a phrase, or practise with a reference.")
          .font(.callout)
          .foregroundStyle(Studio.secondary)
      }
      Spacer(minLength: 8)
      Label("On this Mac", systemImage: "lock")
        .font(.caption)
        .foregroundStyle(Studio.secondary)
    }
    .padding(.horizontal, 4)
    .padding(.top, 4)
  }

  private var captureBar: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Label(
          model.isRecording ? "Recording" : "New recording",
          systemImage: model.isRecording ? "record.circle.fill" : "waveform"
        )
        .font(.headline)
        .foregroundStyle(model.isRecording ? Color.red : Studio.ink)

        if model.isRecording || model.isAnalyzing || model.isRequestingPermission {
          LiveMeterView(level: model.liveLevel)
            .frame(maxWidth: .infinity)
          Text(captureStatusText)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Studio.secondary)
            .frame(width: 78, alignment: .trailing)
        } else {
          Spacer()
        }

        Button(action: model.importClip) {
          Label("Import…", systemImage: "square.and.arrow.down")
        }
        .tint(.primary)
        .studioGlassButton()
        .disabled(model.isRecording || model.isAnalyzing || model.isRequestingPermission)

        Button(action: model.startMimic) {
          Label("Reference practice…", systemImage: "waveform.path")
        }
        .tint(.primary)
        .studioGlassButton()
        .disabled(model.isRecording || model.isAnalyzing || model.isRequestingPermission)

        Button(action: model.startHomeRecording) {
          Label(recordTitle, systemImage: model.isRecording ? "stop.fill" : "record.circle")
        }
        .tint(model.isRecording ? .red : Studio.accent)
        .studioGlassButton(prominent: true)
        .keyboardShortcut(.space, modifiers: [])
        .disabled(model.isAnalyzing || model.isRequestingPermission)
        .accessibilityLabel(
          model.isRecording
            ? "Stop recording"
            : model.isRequestingPermission ? "Waiting for microphone access" : "Record")
      }

      if !model.isRecording && !model.isAnalyzing && !model.isRequestingPermission {
        SettingsLink {
          Label("Transcription settings", systemImage: "globe")
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .help("Choose the transcription engine and spoken language.")
      }

      if model.isAnalyzing {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("Analyzing…")
            .font(.caption)
            .foregroundStyle(Studio.secondary)
        }
      }
    }
    .padding(14)
    .desktopPanel()
  }

  private var recordTitle: String {
    if model.isRecording { return "Stop" }
    if model.isRequestingPermission { return "Waiting…" }
    return "Record"
  }

  private var captureStatusText: String {
    if model.isRecording { return vcDuration(model.elapsed) }
    if model.isAnalyzing { return "Analyzing" }
    return "Mic"
  }

  private var activityRow: some View {
    HStack(spacing: 8) {
      activityChip("\(model.userRecordedTakeCount)", "recordings")
      activityChip(vcNumber(model.userRecordedDuration / 60, 1), "min recorded")
      activityChip("\(model.importedTakeCount)", "imported")
      activityChip("\(model.mimicSessions.count)", "practice sessions")
      Spacer()
    }
    .padding(.horizontal, 4)
  }

  private func activityChip(_ value: String, _ label: String) -> some View {
    HStack(spacing: 5) {
      Text(value)
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(Studio.ink)
      Text(label)
        .font(.caption)
        .foregroundStyle(Studio.secondary)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 3.5)
    .background(Studio.line, in: Capsule())
    .accessibilityElement(children: .combine)
  }

  private func continueMimicCard(_ session: CoachingSession) -> some View {
    Button {
      model.resumeSession(session.id)
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "waveform.path")
          .foregroundStyle(Studio.accent)
          .frame(width: 22)
        VStack(alignment: .leading, spacing: 2) {
          Text("Continue practice")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Studio.secondary)
          Text(session.mimicReference?.sourceName ?? session.name)
            .font(.body.weight(.medium))
            .lineLimit(1)
          Text("\(session.takeCount) \(session.takeCount == 1 ? "take" : "takes")")
            .font(.caption)
            .foregroundStyle(Studio.secondary)
        }
        Spacer()
        Image(systemName: "arrow.right")
          .foregroundStyle(Studio.secondary)
      }
      .padding(14)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .desktopPanel()
    .accessibilityLabel("Continue practice, \(session.mimicReference?.sourceName ?? session.name)")
  }

  private var recentRecordings: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        SectionEyebrow(text: "Recent recordings")
        Spacer()
        if !model.libraryRecordings.isEmpty {
          Button("Library") { model.navigate(to: .library) }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Studio.accent)
        }
      }
      .padding(.horizontal, 14)
      .frame(height: 42)

      Divider()

      let recents = model.libraryRecordings.prefix(8)
      if recents.isEmpty {
        ContentUnavailableView {
          Label("No recordings yet", systemImage: "mic")
        } description: {
          Text("Record or import a clip to listen back and review your delivery.")
        }
        .frame(maxWidth: .infinity, minHeight: 220)
      } else {
        ForEach(recents) { recording in
          Button {
            model.openTake(sessionID: recording.sessionID, takeID: recording.take.id)
          } label: {
            recordingRow(recording)
          }
          .buttonStyle(.plain)
          .studioHoverLift()
          .accessibilityLabel(recording.accessibilityLabel)

          if recording.id != recents.last?.id {
            Divider().padding(.leading, 48)
          }
        }
      }
    }
    .desktopPanel()
  }

  private func recordingRow(_ recording: LibraryRecording) -> some View {
    HStack(spacing: 12) {
      Image(systemName: recording.iconSymbol)
        .foregroundStyle(Studio.accent)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(recording.displayTitle)
          .font(.body.weight(.medium))
          .lineLimit(1)
        Text(rowSubtitle(for: recording))
          .font(.caption)
          .foregroundStyle(Studio.secondary)
          .lineLimit(1)
      }
      Spacer()
      Text(vcDuration(recording.take.result.metrics.duration))
        .font(.caption.monospacedDigit())
        .foregroundStyle(Studio.secondary)
    }
    .padding(.horizontal, 14)
    .frame(height: 58)
    .contentShape(Rectangle())
  }

  private func rowSubtitle(for recording: LibraryRecording) -> String {
    if hideTranscriptSnippets { return recording.subtitle }
    guard
      let snippet = recording.take.transcription?.text.split(separator: " ").prefix(12).joined(
        separator: " "),
      !snippet.isEmpty
    else {
      return recording.subtitle
    }
    return snippet
  }
}
