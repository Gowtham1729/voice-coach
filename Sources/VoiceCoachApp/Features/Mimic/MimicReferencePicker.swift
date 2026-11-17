import SwiftUI

struct MimicReferencePicker: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if model.mimicIsPreparing {
        ProgressView(model.mimicIsFindingPhrases ? "Finding phrases…" : "Preparing audio…")
          .frame(maxWidth: .infinity, minHeight: 100)
      } else if model.isCapturingMimicReference {
        HStack(spacing: 12) {
          Label("Capturing Mac audio", systemImage: "speaker.wave.2")
          LiveMeterView(level: model.mimicReferenceCaptureLevel)
            .frame(maxWidth: .infinity)
          Text(vcDuration(model.mimicReferenceCaptureElapsed))
            .font(.caption.monospacedDigit())
          Button("Stop", action: model.captureMimicReferencePressed)
            .studioGlassButton(prominent: true)
        }
        .frame(minHeight: 100)
      } else {
        HStack(spacing: 14) {
          Button(
            "Import clip…", systemImage: "square.and.arrow.down",
            action: model.chooseMimicReference
          )
          .studioGlassButton()
          Button(
            "Capture Mac audio", systemImage: "speaker.wave.2",
            action: model.captureMimicReferencePressed
          )
          .studioGlassButton()
        }
        .frame(maxWidth: .infinity, minHeight: 100)
      }
      SpeechLanguagePicker()
        .disabled(model.isCapturingMimicReference || model.mimicIsPreparing)
    }
    .padding(16)
    .desktopPanel()
  }
}
