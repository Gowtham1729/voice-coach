import SwiftUI
import VoiceCoachSession

struct HomeView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    StudioPage(maxWidth: 1100, horizontalPadding: 20) {
      VStack(alignment: .leading, spacing: 16) {
        welcome
        captureBar
        if let mimic = model.continueMimic {
          continueMimicCard(mimic)
        }
      }
    }
  }

  private var welcome: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Start a practice")
          .font(.title2.weight(.semibold))
        Text("Record yourself, import a clip, or practice against a reference.")
          .font(.callout)
          .foregroundStyle(Studio.secondary)
      }
      Spacer(minLength: 8)
    }
    .padding(.horizontal, 4)
    .padding(.top, 4)
  }

  private var captureBar: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Label(
          model.isRecording ? "Recording" : "New practice",
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
          Label("Practice with reference…", systemImage: "waveform.path")
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
          Text(TakeScreenCopy.analyzing)
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
    .disabled(!model.canNavigate)
    .desktopPanel()
    .accessibilityLabel("Continue practice, \(session.mimicReference?.sourceName ?? session.name)")
  }
}
