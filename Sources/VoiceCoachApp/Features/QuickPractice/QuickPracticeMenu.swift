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

      VStack(alignment: .leading, spacing: 8) {
        captureControls
      }
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
        QuickPracticeAction(title: "Cancel capture", systemImage: "xmark", showsChevron: false) {
          model.discardMenuBarReference()
        }
      }
    } else if model.isCapturingMimicReference {
      captureHeading("Capturing Mac audio", icon: "record.circle", elapsed: model.mimicReferenceCaptureElapsed)
      LiveMeterView(level: model.mimicReferenceCaptureLevel, accessibilityName: "Mac audio level")
        .padding(.horizontal, 8)
      HStack {
        Text(model.mimicReferenceCaptureLevel > -60 ? "Receiving audio" : "Play audio on your Mac")
        Spacer()
        Text("90 sec max")
      }
      .font(.caption).foregroundStyle(.secondary)
      .padding(.horizontal, 8)
      QuickPracticeAction(title: "Stop and review", systemImage: "stop.fill") {
        if model.hasMenuBarReference {
          model.reviewMenuBarReference()
        } else {
          model.finishMimicReferenceCapture()
        }
        showIchido()
      }
      if model.hasMenuBarReference {
        discardCaptureAction
      }
    } else if model.hasMenuBarReference {
      if model.mimicIsPreparing {
        preparationStatus("Preparing your clip…")
        caption("Your capture will be ready shortly.")
      } else {
        captureHeading("Clip ready", icon: "checkmark.circle", elapsed: model.mimicDraft?.duration)
        caption("Choose a phrase, then listen and repeat.")
        QuickPracticeAction(title: "Review capture…", systemImage: "waveform") {
          model.reviewMenuBarReference()
          showIchido()
        }
      }
      discardCaptureAction
        .disabled(model.destination == .mimicStart)
    } else if model.isRecording {
      captureHeading("Recording my voice", icon: "mic", elapsed: model.elapsed)
      LiveMeterView(level: model.liveLevel).padding(.horizontal, 8)
      QuickPracticeAction(title: "Stop and save", systemImage: "stop.fill") {
        model.stopRecording()
        showIchido()
      }
    } else if model.isAnalyzing || model.mimicIsPreparing {
      preparationStatus("Preparing audio…")
    } else if model.mimicDraft != nil || model.destination == .mimicStart {
      QuickPracticeAction(
        title: "Finish reference practice…", systemImage: "waveform",
        detail: "Finish or cancel the current reference."
      ) { showIchido() }
    } else if model.mimicPhase != .ready || model.hasPendingMimicWork {
      QuickPracticeAction(title: "Return to practice", systemImage: "waveform") { showIchido() }
    } else {
      QuickPracticeAction(
        title: "Capture Mac audio", systemImage: "speaker.wave.2",
        showsChevron: false
      ) {
        model.startMenuBarReferenceCapture()
      }
      .disabled(!model.canStartQuickPractice)
      .help("Capture a clip playing on your Mac for reference practice.")
    }
  }

  private var discardCaptureAction: some View {
    QuickPracticeAction(
      title: "Discard capture", systemImage: "trash", role: .destructive, showsChevron: false
    ) { model.discardMenuBarReference() }
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
    .padding(.horizontal, 8)
  }

  private func caption(_ title: String) -> some View {
    Text(title).font(.caption).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 8)
  }

  @ViewBuilder
  private func preparationStatus(_ title: String) -> some View {
    Group {
      if snapshot {
        Label(title, systemImage: "hourglass").font(.callout)
      } else {
        ProgressView(title).controlSize(.small)
      }
    }
    .padding(.horizontal, 8)
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
  var role: ButtonRole? = nil
  var showsChevron = true
  let action: () -> Void

  var body: some View {
    Button(role: role, action: action) {
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
        if showsChevron {
          Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
        }
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
