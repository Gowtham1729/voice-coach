import SwiftUI
import VoiceCoachCore

struct LineChartView: View {
  let points: [TimePoint]
  let color: Color
  let range: ClosedRange<Double>
  var duration: Double? = nil
  /// Max time between consecutive points before the stroke breaks (pause / unvoiced gap).
  /// `nil` derives a threshold from the series so downsampled contours still gap cleanly.
  var maxGap: Double? = nil
  /// When set (pitch charts), also break when successive values jump by more than this many
  /// semitones — avoids vertical hooks from voicing-onset tracking outliers.
  var maxJumpSemitones: Double? = nil

  var body: some View {
    Canvas { context, size in
      guard points.count > 1, let finalTime = duration ?? points.last?.time, finalTime > 0 else {
        return
      }
      let gapLimit = maxGap ?? Self.adaptiveGapThreshold(for: points)
      var path = Path()
      var lastTime: Double?
      var lastValue: Double?
      for point in points {
        let x = TimelineScale.x(for: point.time, duration: finalTime, width: size.width)
        let normalized =
          (point.value - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.001)
        let y = size.height - CGFloat(max(0, min(1, normalized))) * size.height
        let next = CGPoint(x: x, y: y)
        let withinGap: Bool = {
          guard let lastTime else { return false }
          return point.time - lastTime <= gapLimit
        }()
        let withinPitch: Bool = {
          guard let maxJump = maxJumpSemitones,
            let lastValue,
            lastValue > 0,
            point.value > 0
          else { return true }
          return abs(12 * log2(point.value / lastValue)) <= maxJump
        }()
        if withinGap && withinPitch {
          path.addLine(to: next)
        } else {
          path.move(to: next)
        }
        lastTime = point.time
        lastValue = point.value
      }
      context.stroke(
        path, with: .color(color),
        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
  }

  /// Breaks across pauses without fragmenting a downsampled continuous contour.
  /// Uses the lower quartile of successive deltas so long silence outliers don't inflate the limit.
  static func adaptiveGapThreshold(for points: [TimePoint]) -> Double {
    guard points.count > 2 else { return 0.08 }
    let deltas = zip(points, points.dropFirst()).map { $1.time - $0.time }.filter { $0 > 0 }
    guard !deltas.isEmpty else { return 0.08 }
    let sorted = deltas.sorted()
    let q1 = sorted[sorted.count / 4]
    // Dense acoustic frames (~10 ms) → ~80 ms; heavily downsampled speech stays continuous.
    return max(0.06, min(0.35, q1 * 4))
  }
}

struct LabeledLineChart: View {
  let points: [TimePoint]
  let color: Color
  let range: ClosedRange<Double>
  let duration: Double
  let unit: String
  var playbackTime: Double = 0
  var isPlaying: Bool = false
  var highlightedRange: ClosedRange<Double>? = nil
  var maxJumpSemitones: Double? = nil
  var onSeek: ((Double) -> Void)? = nil
  var onScrub: ((Double) -> Void)? = nil

  var body: some View {
    VStack(spacing: 10) {
      HStack(spacing: 12) {
        VStack(alignment: .trailing) {
          Text(label(range.upperBound))
          Spacer()
          Text(label((range.upperBound + range.lowerBound) / 2))
          Spacer()
          Text(label(range.lowerBound))
        }.frame(width: 55, alignment: .trailing)
        ZStack {
          VStack {
            gridline
            Spacer()
            gridline
            Spacer()
            gridline
          }
          if points.count > 1 {
            LineChartView(
              points: points,
              color: color,
              range: range,
              duration: duration,
              maxJumpSemitones: maxJumpSemitones
            )
          } else {
            Text("Not enough voiced audio")
              .font(.system(size: 12)).foregroundStyle(Studio.secondary)
          }
          TimeRangeHighlight(range: highlightedRange, duration: duration)
          if let onSeek {
            InteractiveGraphOverlay(
              duration: duration,
              playbackTime: playbackTime,
              isPlaying: isPlaying,
              points: points,
              unit: unit,
              onSeek: onSeek,
              onScrub: onScrub
            )
          }
        }
      }
      HStack {
        Text("0s")
        Spacer()
        Text(String(format: "%.1fs", duration / 2))
        Spacer()
        Text(String(format: "%.1fs", duration))
      }.padding(.leading, 67)
    }
    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Studio.secondary)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(unit == "Hz" ? "Pitch" : "Loudness") contour")
    .accessibilityValue(
      points.isEmpty
        ? "No measurable contour"
        : "\(points.count) measurements over \(String(format: "%.1f", duration)) seconds, displayed from \(label(range.lowerBound)) to \(label(range.upperBound))"
    )
  }
  private var gridline: some View { Rectangle().fill(Studio.line).frame(height: 1) }
  private func label(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
  }
}

struct TimeRangeHighlight: View {
  let range: ClosedRange<Double>?
  let duration: Double

  var body: some View {
    GeometryReader { geometry in
      if let range, duration > 0 {
        let start = max(0, min(range.lowerBound, duration))
        let end = max(start, min(range.upperBound, duration))
        let x = TimelineScale.x(for: start, duration: duration, width: geometry.size.width)
        let endX = TimelineScale.x(for: end, duration: duration, width: geometry.size.width)
        let width = endX - x
        Rectangle()
          .fill(Studio.accent.opacity(0.13))
          .overlay(alignment: .leading) {
            Rectangle().fill(Studio.accent.opacity(0.8)).frame(width: 1)
          }
          .overlay(alignment: .trailing) {
            Rectangle().fill(Studio.accent.opacity(0.8)).frame(width: 1)
          }
          .frame(width: max(width, 2))
          .offset(x: x)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
