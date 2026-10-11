import AppKit
import SwiftUI

/// A small capture utility. Trimming and practice stay in the main window.
struct QuickPracticeMenu: View {
  @ObservedObject var model: AppModel
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings
  @Environment(\.dismiss) private var dismiss
  @Environment(\.studioSnapshot) private var snapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Ichido").font(.callout.weight(.semibold))
        Spacer()
        optionsMenu
      }
      .padding(.horizontal, 4)

      VStack(alignment: .leading, spacing: 12) {
        captureControls
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)

      if let message = model.errorMessage {
        VStack(alignment: .leading, spacing: 5) {
          Label(model.errorTitle, systemImage: "exclamationmark.triangle")
            .font(.callout.weight(.medium))
          Text(model.errorTitle == "Capture failed"
            ? "Play a clip while capturing. Check recording permissions if audio stays silent."
            : message)
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Button("Show details…") { showIchido() }
            .buttonStyle(.plain).font(.caption).foregroundStyle(Studio.accent)
        }
        .padding(.horizontal, 4)
      }

      VStack(spacing: 2) {
        if let session = model.continueMimic {
          QuickPracticeAction(
            title: "Continue practice", systemImage: "arrow.clockwise",
            detail: session.name, trailing: session.mimicReference.map {
              vcDuration($0.take.result.metrics.duration)
            }
          ) {
            model.resumeSession(session.id)
            showIchido()
          }
          .disabled(!model.canStartQuickPractice)
          .help(session.name)
        }
        QuickPracticeAction(title: "Record my voice", systemImage: "mic") {
          model.startHomeRecording()
          showIchido()
        }
        .disabled(!model.canStartQuickPractice)
      }

      Divider()
      QuickPracticeAction(title: "Open Ichido", systemImage: "macwindow") { showIchido() }
    }
    .padding(12)
    .frame(width: 320)
  }

  @ViewBuilder
  private var captureControls: some View {
    if model.isRequestingPermission {
      preparationStatus("Waiting for permission…")
      caption("Respond to the macOS permission prompt.")
      if model.hasMenuBarReference {
        Button("Cancel capture") { model.discardMenuBarReference() }
          .studioGlassButton()
      }
    } else if model.isCapturingMimicReference {
      captureHeading("Capturing Mac audio", icon: "record.circle", elapsed: model.mimicReferenceCaptureElapsed)
      LiveMeterView(level: model.mimicReferenceCaptureLevel, accessibilityName: "Mac audio level")
      HStack {
        Text(model.mimicReferenceCaptureLevel > -60 ? "Receiving audio" : "Play audio on your Mac")
        Spacer()
        Text("90 sec max")
      }
      .font(.caption).foregroundStyle(.secondary)
      HStack {
        if model.hasMenuBarReference {
          Button("Discard", role: .destructive) { model.discardMenuBarReference() }
            .studioGlassButton()
        }
        Button {
          if model.hasMenuBarReference {
            model.reviewMenuBarReference()
          } else {
            model.finishMimicReferenceCapture()
          }
          showIchido()
        } label: {
          Label("Stop and review", systemImage: "stop.fill")
            .frame(maxWidth: .infinity)
        }
        .studioGlassButton(prominent: true)
      }
    } else if model.hasMenuBarReference {
      if model.mimicIsPreparing {
        preparationStatus("Preparing your clip…")
        caption("Your capture will be ready shortly.")
      } else {
        captureHeading("Clip ready", icon: "checkmark.circle", elapsed: model.mimicDraft?.duration)
        caption("Choose a phrase, then listen and repeat.")
        Button {
          model.reviewMenuBarReference()
          showIchido()
        } label: {
          Label("Review capture…", systemImage: "waveform")
            .frame(maxWidth: .infinity)
        }
        .studioGlassButton(prominent: true)
      }
      Button("Discard capture", role: .destructive) { model.discardMenuBarReference() }
        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        .disabled(model.destination == .mimicStart)
    } else if model.isRecording {
      captureHeading("Recording my voice", icon: "mic", elapsed: model.elapsed)
      LiveMeterView(level: model.liveLevel)
      Button {
        model.stopRecording()
        showIchido()
      } label: {
        Label("Stop and save", systemImage: "stop.fill").frame(maxWidth: .infinity)
      }
      .studioGlassButton(prominent: true)
    } else if model.isAnalyzing || model.mimicIsPreparing {
      preparationStatus("Preparing audio…")
    } else if model.mimicDraft != nil || model.destination == .mimicStart {
      captureHeading("Reference in progress", icon: "waveform")
      caption("Finish or cancel the reference in Ichido.")
      Button("Finish reference practice…") { showIchido() }
        .studioGlassButton()
    } else if model.mimicPhase != .ready || model.hasPendingMimicWork {
      captureHeading("Practice in progress", icon: "waveform")
      Button("Return to practice") { showIchido() }
        .studioGlassButton()
    } else {
      captureHeading("Capture a phrase", icon: "speaker.wave.2")
      caption("Play a video, podcast, or other Mac audio.")
      Button {
        model.startMenuBarReferenceCapture()
      } label: {
        Text("Capture Mac audio").frame(maxWidth: .infinity)
      }
      .disabled(!model.canStartQuickPractice)
      .studioGlassButton(prominent: true)
    }
  }

  @ViewBuilder
  private var optionsMenu: some View {
    // Menu is AppKit-backed and cannot be drawn by ImageRenderer.
    if snapshot {
      Image(systemName: "ellipsis").frame(width: 24, height: 24)
    } else {
      Menu {
        Button("Settings…", systemImage: "gearshape") { showSettings() }
        Divider()
        Button("Quit Ichido") { NSApp.terminate(nil) }
      } label: {
        Image(systemName: "ellipsis").frame(width: 24, height: 24)
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .accessibilityLabel("Ichido options")
      .help("Settings and Quit")
    }
  }

  private func captureHeading(_ title: String, icon: String, elapsed: Double? = nil) -> some View {
    HStack(spacing: 7) {
      Label(title, systemImage: icon).font(.callout.weight(.semibold))
      Spacer(minLength: 4)
      if let elapsed {
        Text(vcDuration(elapsed)).font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
          .accessibilityLabel("Duration \(vcDuration(elapsed))")
      }
    }
  }

  private func caption(_ title: String) -> some View {
    Text(title).font(.caption).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private func preparationStatus(_ title: String) -> some View {
    if snapshot {
      Label(title, systemImage: "hourglass").font(.callout)
    } else {
      ProgressView(title).controlSize(.small)
    }
  }

  private func showSettings() {
    dismiss()
    openSettings()
    NSApp.activate(ignoringOtherApps: true)
  }

  private func showIchido() {
    dismiss()
    IchidoMainWindow.show(openWindow: openWindow)
  }
}

private struct QuickPracticeAction: View {
  let title: String
  let systemImage: String
  var detail: String? = nil
  var trailing: String? = nil
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: systemImage).frame(width: 18)
          .foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 3) {
          Text(title).font(.callout)
          if let detail {
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
        }
        Spacer(minLength: 4)
        if let trailing {
          Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 8).padding(.vertical, 8)
      .contentShape(Rectangle())
    }
    .buttonStyle(QuickPracticeRowStyle())
  }
}

private struct QuickPracticeRowStyle: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  @State private var hovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background {
        RoundedRectangle(cornerRadius: 6)
          .fill(Color.primary.opacity(enabled && (hovering || configuration.isPressed) ? 0.08 : 0))
      }
      .opacity(enabled ? 1 : 0.45)
      .onHover { hovering = $0 }
  }
}
