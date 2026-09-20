import AppKit
import SwiftUI
import VoiceCoachCore

extension TakeView {
  func copyTranscript(_ text: String) {
    guard !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    isTranscriptCopied = true
    model.toastMessage = "Transcript copied"
  }

  @MainActor
  func copyAnalysisSnapshot(_ take: PracticeSession) {
    let renderer = ImageRenderer(content: analysisClipboardSnapshot(take))
    renderer.scale = 2

    guard let image = renderer.nsImage else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([image])
    if let cgImage = renderer.cgImage,
      let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    {
      pasteboard.setData(data, forType: .png)
    }
    isGraphCopied = true
    model.toastMessage = "\(selectedPlot.rawValue) graph copied"
  }

  func analysisClipboardSnapshot(_ take: PracticeSession) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("VOICE COACH · \(selectedPlot.rawValue.uppercased()) ANALYSIS")
          .font(.system(size: 10, weight: .semibold))
          .tracking(1.8)
          .foregroundStyle(Studio.secondary)
        Spacer()
        Text("\(vcNumber(take.result.metrics.duration, 1))s")
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(Studio.secondary)
      }
      activePlot(take, highlightedRange: selectedRange(take), interactive: false)
        .frame(height: 225)
      Divider()
      AlignedWaveformRow(
        points: take.result.waveform,
        duration: take.result.metrics.duration,
        highlightedRange: selectedRange(take)
      )
      .frame(height: 46)
    }
    .padding(24)
    .frame(width: 980)
    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 18))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Studio.line))
    .environment(\.studioSnapshot, true)
  }

  func pitchBounds(_ result: AnalysisResult) -> ClosedRange<Double> {
    let values = result.pitchContour.map(\.value).filter { $0.isFinite && $0 > 0 }
    let low = floor(((values.min() ?? 100) - 25) / 25) * 25
    let high = ceil(((values.max() ?? 250) + 25) / 25) * 25
    return max(0, low)...max(high, low + 50)
  }
}
