import SwiftUI
import VoiceCoachCore

struct WaveformView: View {
  let points: [WaveformPoint]
  let duration: Double
  var color: Color = Studio.accent

  var body: some View {
    Canvas { context, size in
      guard !points.isEmpty else { return }
      let middle = size.height / 2
      var baseline = Path()
      baseline.move(to: CGPoint(x: 0, y: middle))
      baseline.addLine(to: CGPoint(x: size.width, y: middle))
      context.stroke(baseline, with: .color(Studio.line), lineWidth: 1)
      var path = Path()
      for (index, point) in points.enumerated() {
        // Each amplitude bin represents the center of an equal portion of the recording.
        // Mapping it through TimelineScale keeps it in the exact same time space as the charts.
        let time = (Double(index) + 0.5) / Double(points.count) * duration
        let x = TimelineScale.x(for: time, duration: duration, width: size.width)
        path.move(to: CGPoint(x: x, y: middle - CGFloat(point.maximum) * middle))
        path.addLine(to: CGPoint(x: x, y: middle - CGFloat(point.minimum) * middle))
      }
      context.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 1)
    }
    .accessibilityLabel("Waveform")
  }
}

struct InteractiveWaveformView: View {
  let points: [WaveformPoint]
  let duration: Double
  var playbackTime: Double = 0
  var isPlaying: Bool = false
  var color: Color = Studio.accent
  var highlightedRange: ClosedRange<Double>? = nil
  var onSeek: ((Double) -> Void)? = nil
  var onScrub: ((Double) -> Void)? = nil

  var body: some View {
    ZStack {
      WaveformView(points: points, duration: duration, color: color)
      TimeRangeHighlight(range: highlightedRange, duration: duration)
      if let onSeek {
        InteractiveGraphOverlay(
          duration: duration,
          playbackTime: playbackTime,
          isPlaying: isPlaying,
          points: nil,
          unit: nil,
          showBadge: false,
          onSeek: onSeek,
          onScrub: onScrub
        )
      }
    }
  }
}

/// A waveform row that shares the exact left gutter and time width of `LabeledLineChart`.
/// Use it directly beneath an analysis chart so playheads line up in screen space.
struct AlignedWaveformRow: View {
  let points: [WaveformPoint]
  let duration: Double
  var playbackTime: Double = 0
  var isPlaying = false
  var highlightedRange: ClosedRange<Double>? = nil
  var onSeek: ((Double) -> Void)? = nil
  var onScrub: ((Double) -> Void)? = nil

  var body: some View {
    HStack(spacing: 12) {
      VStack(spacing: 3) {
        Image(systemName: "waveform")
          .font(.system(size: 11, weight: .medium))
        Text(String(format: "%.1fs", duration))
          .font(.system(size: 8, design: .monospaced))
      }
      .foregroundStyle(Studio.secondary)
      .frame(width: 55, alignment: .trailing)

      InteractiveWaveformView(
        points: points,
        duration: duration,
        playbackTime: playbackTime,
        isPlaying: isPlaying,
        highlightedRange: highlightedRange,
        onSeek: onSeek,
        onScrub: onScrub
      )
    }
  }
}
