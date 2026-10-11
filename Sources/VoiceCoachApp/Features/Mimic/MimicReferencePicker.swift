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

struct ManualPracticeExcerptView: View {
  let draft: MimicReferenceDraft
  @Binding var start: Double
  @Binding var end: Double
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot
  @State private var viewportStart = 0.0

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(model.suggestedPracticeClips.isEmpty
        ? "No phrases found. Choose a clip to practise."
        : "Drag the handles to choose a clip.")
        .font(.callout).foregroundStyle(Studio.secondary)
      MimicTrimWaveform(
        peaks: draft.peaks, duration: draft.duration,
        viewportStart: viewportStart, viewportDuration: min(30, draft.duration),
        start: $start, end: $end
      )
      .frame(height: 82)
      if draft.duration > 30 {
        if snapshot {
          Capsule().fill(Studio.accent.opacity(0.3)).frame(height: 5)
        } else {
          Slider(value: Binding(
            get: { viewportStart },
            set: { position in
              let length = min(30, max(1, end - start))
              viewportStart = min(max(0, position), draft.duration - 30)
              start = viewportStart
              end = min(draft.duration, start + length)
            }), in: 0...(draft.duration - 30))
            .accessibilityLabel("Browse audio")
        }
      }
      HStack {
        Button(model.isPlaying ? "Stop" : "Play clip") {
          if model.isPlaying { model.stopPlayback() }
          else { model.playMimicDraft(start: start, end: end) }
        }
        .disabled(end - start < 1)
        Spacer()
        Text("\(vcNumber(start, 1))–\(vcNumber(end, 1))s")
          .font(.caption.monospacedDigit()).foregroundStyle(Studio.secondary)
      }
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
        handle(at: left, width: width, isStart: true)
        handle(at: right, width: width, isStart: false)
      }
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
        if isStart {
          start = min(max(0, start + delta), end - 1)
        } else {
          end = max(min(duration, end + delta), start + 1)
        }
      }
  }
}
