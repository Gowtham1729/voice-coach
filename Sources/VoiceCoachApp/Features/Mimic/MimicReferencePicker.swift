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
          Button("Import clip…", systemImage: "square.and.arrow.down",
            action: model.chooseMimicReference)
            .studioGlassButton()
          Button("Capture Mac audio", systemImage: "speaker.wave.2",
            action: model.captureMimicReferencePressed)
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

struct MimicTrimWaveform: View {
  let peaks: [Float]
  let duration: Double
  let viewportStart: Double
  let viewportDuration: Double
  @Binding var start: Double
  @Binding var end: Double
  var playbackTime: Double? = nil
  @State private var startDragOrigin: Double?
  @State private var endDragOrigin: Double?

  var body: some View {
    GeometryReader { geometry in
      let width = max(geometry.size.width, 1)
      let visible = max(viewportDuration, 1)
      let left = CGFloat((start - viewportStart) / visible) * width
      let right = CGFloat((end - viewportStart) / visible) * width
      ZStack(alignment: .leading) {
        Canvas { context, size in
          guard !peaks.isEmpty else { return }
          let first = max(0, Int(Double(peaks.count) * viewportStart / duration))
          let last = min(
            peaks.count, Int(ceil(Double(peaks.count) * (viewportStart + visible) / duration)))
          guard first < last else { return }
          for index in first..<last {
            let time = Double(index) / Double(peaks.count) * duration
            let x = CGFloat((time - viewportStart) / visible) * size.width
            let height = max(2, CGFloat(min(peaks[index], 1)) * size.height * 0.8)
            let barWidth = max(
              1, size.width * CGFloat(duration / visible) / CGFloat(peaks.count) - 1)
            let bar = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
            context.fill(
              Path(roundedRect: bar, cornerRadius: 1),
              with: .color(Studio.accent.opacity(x >= left && x <= right ? 0.95 : 0.32)))
          }
        }
        Rectangle()
          .fill(Studio.accent.opacity(0.08))
          .frame(width: max(0, right - left))
          .offset(x: left)
          .allowsHitTesting(false)
        if left >= 0, left <= width {
          handle(at: min(max(4, left), width - 4), width: width, isStart: true)
        }
        if right >= 0, right <= width {
          handle(at: min(max(4, right), width - 4), width: width, isStart: false)
        }
        if let playbackTime, playbackTime >= viewportStart,
          playbackTime <= viewportStart + visible {
          Rectangle().fill(.primary.opacity(0.7)).frame(width: 1)
            .offset(x: CGFloat((playbackTime - viewportStart) / visible) * width)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
      }
      .clipped()
    }
    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 7))
  }

  private func handle(at x: CGFloat, width: CGFloat, isStart: Bool) -> some View {
    Rectangle()
      .fill(.clear)
      .frame(width: 28, height: 82)
      .overlay {
        RoundedRectangle(cornerRadius: 3)
          .fill(Studio.accent)
          .frame(width: 8, height: 76)
          .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.7), lineWidth: 1))
          .allowsHitTesting(false)
      }
      .contentShape(Rectangle())
      .position(x: x, y: 41)
      .focusable()
      .onKeyPress(.leftArrow) {
        adjustHandle(isStart: isStart, delta: -0.1)
        return .handled
      }
      .onKeyPress(.rightArrow) {
        adjustHandle(isStart: isStart, delta: 0.1)
        return .handled
      }
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { value in
          let change = Double(value.translation.width / width) * viewportDuration
          if isStart {
            if startDragOrigin == nil { startDragOrigin = start }
            start = min(max(viewportStart, (startDragOrigin ?? start) + change), end - 1)
          } else {
            if endDragOrigin == nil { endDragOrigin = end }
            end = max(
              min(viewportStart + viewportDuration, (endDragOrigin ?? end) + change), start + 1)
          }
        }.onEnded { _ in
          if isStart { startDragOrigin = nil } else { endDragOrigin = nil }
        }
      )
      .accessibilityLabel(isStart ? "Excerpt start" : "Excerpt end")
      .accessibilityValue(
        "\((isStart ? start : end).formatted(.number.precision(.fractionLength(1)))) seconds"
      )
      .accessibilityAdjustableAction { direction in
        let delta = direction == .increment ? 0.1 : -0.1
        adjustHandle(isStart: isStart, delta: delta)
      }
      .help("Drag to trim, or use the left and right arrow keys.")
  }

  private func adjustHandle(isStart: Bool, delta: Double) {
    if isStart { start = min(max(0, start + delta), end - 1) }
    else { end = max(min(duration, end + delta), start + 1) }
  }
}
