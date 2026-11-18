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
    VStack(alignment: .leading, spacing: 14) {
      header

      if isIdle {
        HStack(spacing: 10) {
          QuickPracticeTile(
            title: "Record my voice", caption: "Start a new take",
            systemImage: "mic.fill", tint: .red
          ) {
            model.startHomeRecording()
            showIchido()
          }
          QuickPracticeTile(
            title: "Capture Mac audio", caption: "Save a clip to repeat",
            systemImage: "speaker.wave.2.fill", tint: Studio.accent
          ) {
            model.startMenuBarReferenceCapture()
          }
          .help("Capture a clip playing on your Mac for reference practice.")
        }
        .fixedSize(horizontal: false, vertical: true)
        .disabled(!model.canStartQuickPractice)
      } else {
        QuickPracticeCard { activeCapture }
      }

      if model.errorIsFromCapture, let message = model.errorMessage {
        errorBanner(message)
      }

      VStack(spacing: 6) {
        Divider()
        QuickPracticeAction(title: "Open Ichido", systemImage: "macwindow") { showIchido() }
      }
    }
    .padding(14)
    .frame(width: 340)
  }

  /// No capture, recording, or practice owns the panel, so it offers the two starting points.
  private var isIdle: Bool {
    !model.isRequestingPermission && !model.isCapturingMimicReference && !model.hasMenuBarReference
      && !model.isRecording && !model.isAnalyzing && !model.mimicIsPreparing
      && model.mimicDraft == nil && model.destination != .mimicStart
      && model.mimicPhase == .ready && !model.hasPendingMimicWork
  }

  // MARK: - Sections

  private var header: some View {
    HStack(spacing: 10) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable().interpolation(.high)
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text("Ichido").font(.headline)
        Text("Quick practice").font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      optionsMenu
    }
  }

  @ViewBuilder
  private var activeCapture: some View {
    if model.isRequestingPermission {
      preparationStatus("Waiting for permission…")
      caption("Respond to the macOS permission prompt.")
      if model.hasMenuBarReference {
        Button("Cancel capture") { model.discardMenuBarReference() }
          .buttonStyle(QuickPracticeButtonStyle())
      }
    } else if model.isCapturingMimicReference {
      liveHeading("Capturing Mac audio", elapsed: model.mimicReferenceCaptureElapsed)
      LiveMeterView(level: model.mimicReferenceCaptureLevel, accessibilityName: "Mac audio level")
      HStack {
        Text(model.mimicReferenceCaptureLevel > -60 ? "Receiving audio" : "Play audio on your Mac")
        Spacer()
        Text("90 sec max")
      }
      .font(.caption).foregroundStyle(.secondary)
      HStack(spacing: 8) {
        Button("Stop and review") {
          if model.hasMenuBarReference {
            model.reviewMenuBarReference()
          } else {
            model.finishMimicReferenceCapture()
          }
          showIchido()
        }
        .buttonStyle(QuickPracticeButtonStyle(prominent: true))
        if model.hasMenuBarReference { discardCaptureButton }
      }
    } else if model.hasMenuBarReference {
      if model.mimicIsPreparing {
        preparationStatus("Preparing your clip…")
        caption("Your capture will be ready shortly.")
        discardCaptureButton
      } else {
        heading(
          "Clip ready", icon: "checkmark.circle.fill", tint: .green,
          elapsed: model.mimicDraft?.duration)
        caption("Choose a phrase, then listen and repeat.")
        HStack(spacing: 8) {
          Button("Review capture…") {
            model.reviewMenuBarReference()
            showIchido()
          }
          .buttonStyle(QuickPracticeButtonStyle(prominent: true))
          discardCaptureButton.disabled(model.destination == .mimicStart)
        }
      }
    } else if model.isRecording {
      liveHeading("Recording my voice", elapsed: model.elapsed)
      LiveMeterView(level: model.liveLevel)
      Button("Stop and save") {
        model.stopRecording()
        showIchido()
      }
      .buttonStyle(QuickPracticeButtonStyle(prominent: true))
    } else if model.isAnalyzing || model.mimicIsPreparing {
      preparationStatus("Preparing audio…")
    } else if model.mimicDraft != nil || model.destination == .mimicStart {
      heading("Reference practice", icon: "waveform", tint: Studio.accent)
      caption("Finish or cancel the current reference.")
      Button("Finish reference practice…") { showIchido() }
        .buttonStyle(QuickPracticeButtonStyle(prominent: true))
    } else {
      heading("Practice in progress", icon: "waveform", tint: Studio.accent)
      Button("Return to practice") { showIchido() }
        .buttonStyle(QuickPracticeButtonStyle(prominent: true))
    }
  }

  private var discardCaptureButton: some View {
    Button("Discard capture", role: .destructive) { model.discardMenuBarReference() }
      .buttonStyle(QuickPracticeButtonStyle())
  }

  private func errorBanner(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(model.errorTitle, systemImage: "exclamationmark.triangle.fill")
        .font(.callout.weight(.medium))
        .foregroundStyle(.orange)
      Text(message)
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button("Dismiss") { model.clearError() }
        .buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(Studio.accent)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.10)))
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

  // MARK: - Pieces

  private func liveHeading(_ title: String, elapsed: Double) -> some View {
    HStack(spacing: 8) {
      LiveDot()
      Text(title).font(.callout.weight(.semibold))
      Spacer(minLength: 4)
      elapsedText(elapsed)
    }
  }

  private func heading(_ title: String, icon: String, tint: Color, elapsed: Double? = nil)
    -> some View
  {
    HStack(spacing: 8) {
      Image(systemName: icon).foregroundStyle(tint)
      Text(title).font(.callout.weight(.semibold))
      Spacer(minLength: 4)
      if let elapsed { elapsedText(elapsed) }
    }
  }

  private func elapsedText(_ seconds: Double) -> some View {
    Text(vcDuration(seconds))
      .font(.title3.monospacedDigit().weight(.medium))
      .accessibilityLabel("Duration \(vcDuration(seconds))")
  }

  private func caption(_ title: String) -> some View {
    Text(title).font(.caption).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func preparationStatus(_ title: String) -> some View {
    Group {
      if snapshot {
        Label(title, systemImage: "hourglass").font(.callout.weight(.medium))
      } else {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text(title).font(.callout.weight(.medium))
        }
      }
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

// MARK: - Building blocks

/// A rounded surface that groups the controls for whatever currently owns the panel.
private struct QuickPracticeCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) { content }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background {
        RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05))
          .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
      }
  }
}

private struct QuickPracticeTile: View {
  let title: String
  let caption: String
  let systemImage: String
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        Image(systemName: systemImage)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 32, height: 32)
          .background(Circle().fill(tint.gradient))
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.callout.weight(.semibold))
          Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(12)
      .contentShape(Rectangle())
    }
    .buttonStyle(QuickPracticeCardStyle())
  }
}

private struct QuickPracticeCardStyle: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  @State private var hovering = false

  func makeBody(configuration: Configuration) -> some View {
    let active = enabled && (hovering || configuration.isPressed)
    configuration.label
      .background {
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : active ? 0.09 : 0.05))
          .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
      }
      .opacity(enabled ? 1 : 0.45)
      .onHover { hovering = $0 }
  }
}

/// Full-width capsule button drawn in SwiftUI so preview snapshots match the live panel.
private struct QuickPracticeButtonStyle: ButtonStyle {
  var prominent = false
  @Environment(\.isEnabled) private var enabled
  @State private var hovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.callout.weight(.medium))
      .foregroundStyle(labelColor(role: configuration.role))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 7)
      .background {
        Capsule().fill(
          prominent
            ? AnyShapeStyle(Studio.accent.opacity(configuration.isPressed ? 0.8 : 1))
            : AnyShapeStyle(Color.primary.opacity(configuration.isPressed || hovering ? 0.12 : 0.07)))
      }
      .brightness(prominent && hovering && !configuration.isPressed ? 0.05 : 0)
      .opacity(enabled ? 1 : 0.45)
      .contentShape(Capsule())
      .onHover { hovering = $0 }
  }

  private func labelColor(role: ButtonRole?) -> Color {
    if prominent { return .white }
    if role == .destructive { return .red }
    return .primary
  }
}

private struct LiveDot: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.studioSnapshot) private var snapshot
  @State private var dimmed = false

  var body: some View {
    Circle().fill(Color.red)
      .frame(width: 8, height: 8)
      .opacity(dimmed ? 0.3 : 1)
      .accessibilityHidden(true)
      .onAppear {
        guard !reduceMotion, !snapshot else { return }
        withAnimation(.easeInOut(duration: 0.8).repeatForever()) { dimmed = true }
      }
  }
}

private struct QuickPracticeAction: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: systemImage).frame(width: 18)
          .foregroundStyle(.secondary)
        Text(title).font(.callout)
        Spacer(minLength: 4)
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 8).padding(.vertical, 7)
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
