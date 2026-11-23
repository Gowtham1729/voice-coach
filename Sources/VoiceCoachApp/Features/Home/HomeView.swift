import SwiftUI
import VoiceCoachSession

struct HomeView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    StudioPage(maxWidth: 1100, horizontalPadding: 20) {
      VStack(alignment: .leading, spacing: 16) {
        welcome
        captureBar
        if !model.recentPractices.isEmpty {
          recentPractices
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
      // Wide windows: one row. Narrow: status above, then buttons in a row or a column.
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          captureStatus
          Spacer(minLength: 0)
          actionButtons
        }
        VStack(alignment: .leading, spacing: 10) {
          captureStatus
          HStack(spacing: 8) { actionButtons }
        }
        VStack(alignment: .leading, spacing: 8) {
          captureStatus
          actionButtons
        }
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

  private var isCapturing: Bool {
    model.isRecording || model.isAnalyzing || model.isRequestingPermission
  }

  @ViewBuilder
  private var captureStatus: some View {
    if isCapturing {
      HStack(spacing: 12) {
        Label(
          model.isRecording ? "Recording" : "New practice",
          systemImage: model.isRecording ? "record.circle.fill" : "waveform"
        )
        .font(.headline)
        .foregroundStyle(model.isRecording ? Color.red : Studio.ink)
        .fixedSize()
        LiveMeterView(level: model.liveLevel)
          .frame(minWidth: 80, maxWidth: .infinity)
        Text(captureStatusText)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(Studio.secondary)
          .frame(width: 78, alignment: .trailing)
      }
    }
  }

  @ViewBuilder
  private var actionButtons: some View {
    Button(action: model.importClip) {
      Label("Import…", systemImage: "square.and.arrow.down")
        .fixedSize()
    }
    .tint(.primary)
    .studioGlassButton()
    .disabled(isCapturing)

    Button(action: model.startMimic) {
      Label("Practice with reference…", systemImage: "waveform.path")
        .fixedSize()
    }
    .tint(.primary)
    .studioGlassButton()
    .disabled(isCapturing)

    Button(action: model.startHomeRecording) {
      Label(recordTitle, systemImage: model.isRecording ? "stop.fill" : "record.circle")
        .fixedSize()
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

  private var recentPractices: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Continue practice")
        .font(.caption.weight(.semibold))
        .foregroundStyle(Studio.secondary)
        .padding(.horizontal, 4)
      VStack(spacing: 0) {
        ForEach(Array(model.recentPractices.enumerated()), id: \.element.id) { index, session in
          if index > 0 { Divider().padding(.leading, 48) }
          recentRow(session)
        }
      }
      .desktopPanel()
    }
  }

  private func recentRow(_ session: CoachingSession) -> some View {
    Button {
      model.resumeSession(session.id)
    } label: {
      HStack(spacing: 12) {
        Image(systemName: session.isMimic ? "waveform.path" : "waveform")
          .foregroundStyle(Studio.accent)
          .frame(width: 22)
        VStack(alignment: .leading, spacing: 2) {
          Text(PracticeCatalog.title(of: session))
            .font(.body.weight(.medium))
            .lineLimit(1)
          Text(PracticeCatalog.detail(of: session))
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
    .accessibilityLabel("Continue practice, \(PracticeCatalog.title(of: session))")
  }
}
