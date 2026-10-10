import AppKit
import SwiftUI

struct QuickPracticeMenu: View {
  @ObservedObject var model: AppModel
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Ichido").font(.headline)
          Text("Quick practice").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Image(nsImage: IchidoMenuBarIcon.idle)
          .accessibilityHidden(true)
      }

      captureControls

      if let message = model.errorMessage {
        VStack(alignment: .leading, spacing: 6) {
          Label(model.errorTitle, systemImage: "exclamationmark.triangle")
            .font(.callout.weight(.medium))
          Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          Button("Show details…") { showIchido() }
        }
      }

      Divider()

      if let session = model.continueMimic {
        Button {
          model.resumeSession(session.id)
          showIchido()
        } label: {
          Label("Continue practice", systemImage: "arrow.clockwise")
        }
        .disabled(!model.canStartQuickPractice)
        .help(session.name)
      }

      Button {
        model.startHomeRecording()
        showIchido()
      } label: {
        Label("Record my voice", systemImage: "mic")
      }
      .disabled(!model.canStartQuickPractice)

      Button("Open Ichido") { showIchido() }

      HStack {
        Button("Settings…") {
          dismiss()
          openSettings()
          NSApp.activate(ignoringOtherApps: true)
        }
        Spacer()
        Button("Quit Ichido") { NSApp.terminate(nil) }
      }
    }
    .buttonStyle(.plain)
    .padding(18)
    .frame(width: 310)
  }

  @ViewBuilder
  private var captureControls: some View {
    if model.isCapturingMimicReference {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Label("Capturing Mac audio", systemImage: "record.circle.fill")
            .font(.callout.weight(.semibold))
          Spacer(minLength: 4)
          Text(vcDuration(model.mimicReferenceCaptureElapsed))
            .font(.caption.monospacedDigit())
        }
        LiveMeterView(level: model.mimicReferenceCaptureLevel, accessibilityName: "Mac audio level")
        Text("Play a clip on your Mac. Capture stops after 90 seconds.")
          .font(.caption).foregroundStyle(.secondary)
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

        if model.hasMenuBarReference {
          Button("Discard capture", role: .destructive) { model.discardMenuBarReference() }
        }
      }
    } else if model.hasMenuBarReference {
      if model.mimicIsPreparing {
        ProgressView("Preparing reference…").controlSize(.small)
      } else {
        Text("Your captured clip is ready.").font(.callout)
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
        .disabled(model.destination == .mimicStart)
    } else if model.isRecording {
      HStack {
        Label("Recording my voice", systemImage: "mic.fill")
        Spacer()
        Text(vcDuration(model.elapsed)).monospacedDigit()
      }
      .font(.callout)
      Button {
        model.stopRecording()
        showIchido()
      } label: {
        Label("Stop and save", systemImage: "stop.fill").frame(maxWidth: .infinity)
      }
      .studioGlassButton(prominent: true)
    } else if model.isAnalyzing || model.mimicIsPreparing || model.isRequestingPermission {
      ProgressView(model.isRequestingPermission ? "Waiting for permission…" : "Preparing audio…")
        .controlSize(.small)
    } else if model.mimicDraft != nil || model.destination == .mimicStart {
      Button("Finish reference practice…") { showIchido() }
      Text("Finish or cancel the current reference before capturing another.")
        .font(.caption).foregroundStyle(.secondary)
    } else if model.mimicPhase != .ready || model.hasPendingMimicWork {
      Button("Return to practice") { showIchido() }
      Text("Finish the current take before capturing a reference.")
        .font(.caption).foregroundStyle(.secondary)
    } else {
      Button {
        model.startMenuBarReferenceCapture()
      } label: {
        Label("Capture Mac audio", systemImage: "speaker.wave.2")
          .frame(maxWidth: .infinity)
      }
      .disabled(!model.canStartQuickPractice)
      .studioGlassButton(prominent: true)
      Text("Capture what your Mac is playing, then choose a phrase to practise.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func showIchido() {
    dismiss()
    IchidoMainWindow.show(openWindow: openWindow)
  }
}
