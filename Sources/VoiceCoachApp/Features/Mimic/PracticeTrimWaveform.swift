import SwiftUI

struct PracticeTrimWaveform: View {
  static let height: CGFloat = 82
  let peaks: [Float]
  let duration: Double
  @Binding var start: Double
  @Binding var end: Double
  var playbackTime: Double? = nil
  @State private var startDragOrigin: Double?
  @State private var endDragOrigin: Double?

  var body: some View {
    GeometryReader { geometry in
      let width = max(geometry.size.width, 1)
      let left = TimelineScale.x(for: start, duration: duration, width: width)
      let right = TimelineScale.x(for: end, duration: duration, width: width)
      ZStack(alignment: .leading) {
        Canvas { context, size in
          guard !peaks.isEmpty, duration.isFinite, duration > 0 else { return }
          // Pool dense peaks to screen-sized bars so even long clips draw cheaply.
          let barCount = min(peaks.count, max(1, Int(size.width / 3)))
          let spacing = size.width / CGFloat(barCount)
          for index in 0..<barCount {
            let first = index * peaks.count / barCount
            let last = (index + 1) * peaks.count / barCount
            let peak = peaks[first..<last].max() ?? 0
            let amplitude = peak.isFinite ? min(max(peak, 0), 1) : 0
            let x = (CGFloat(index) + 0.5) * spacing
            let height = max(2, CGFloat(amplitude) * size.height * 0.8)
            let bar = CGRect(
              x: x - spacing / 2, y: (size.height - height) / 2,
              width: max(1, spacing - 1), height: height)
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
        handle(at: min(max(4, left), width - 4), width: width, isStart: true)
        handle(at: min(max(4, right), width - 4), width: width, isStart: false)
        if let playbackTime, playbackTime >= 0, playbackTime <= duration {
          Rectangle().fill(.primary.opacity(0.7)).frame(width: 1)
            .offset(x: TimelineScale.x(for: playbackTime, duration: duration, width: width))
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
      .frame(width: 28, height: Self.height)
      .overlay {
        RoundedRectangle(cornerRadius: 3)
          .fill(Studio.accent)
          .frame(width: 8, height: Self.height - 6)
          .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.7), lineWidth: 1))
          .allowsHitTesting(false)
      }
      .contentShape(Rectangle())
      .position(x: x, y: Self.height / 2)
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
          let change = Double(value.translation.width / width) * duration
          if isStart {
            if startDragOrigin == nil { startDragOrigin = start }
            start = min(max(0, (startDragOrigin ?? start) + change), end - 1)
          } else {
            if endDragOrigin == nil { endDragOrigin = end }
            end = max(
              min(duration, (endDragOrigin ?? end) + change), start + 1)
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
    if isStart {
      start = min(max(0, start + delta), end - 1)
    } else {
      end = max(min(duration, end + delta), start + 1)
    }
  }
}
