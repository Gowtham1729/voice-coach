#if os(macOS)
import AppKit
#endif
import SwiftUI
import VoiceCoachCore

enum TimelineScale {
    static func x(for time: Double, duration: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let progress = max(0, min(1, time / duration))
        return CGFloat(progress) * width
    }

    static func time(for x: CGFloat, width: CGFloat, duration: Double) -> Double {
        guard width > 0 else { return 0 }
        let progress = max(0, min(1, x / width))
        return Double(progress) * duration
    }
}

func contourValue(at time: Double, in points: [TimePoint]) -> Double? {
    guard !points.isEmpty else { return nil }
    var closest: TimePoint?
    var minDiff = Double.greatestFiniteMagnitude
    for point in points {
        let diff = abs(point.time - time)
        if diff < minDiff {
            minDiff = diff
            closest = point
        }
        if point.time > time + 0.25 { break }
    }
    if minDiff <= 0.15 {
        return closest?.value
    }
    return nil
}

struct PlayheadView: View {
    let positionX: CGFloat
    let height: CGFloat
    let width: CGFloat
    let labelText: String?
    let isHighlighted: Bool
    let isGhost: Bool

    var body: some View {
        let badgeX = max(42, min(width - 42, positionX))
        let accentColor = isGhost ? Studio.secondary.opacity(0.6) : Studio.accent

        ZStack(alignment: .top) {
            // Vertical playhead line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor,
                            accentColor.opacity(isGhost ? 0.35 : 0.85),
                            accentColor.opacity(isGhost ? 0.15 : 0.45)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: isHighlighted ? 2 : 1.5, height: height)
                .shadow(color: isGhost ? .clear : Studio.accent.opacity(0.55), radius: 3, x: 0, y: 0)
                .position(x: positionX, y: height / 2)

            // Top handle thumb (for active playhead)
            if !isGhost {
                Capsule()
                    .fill(Studio.ink)
                    .frame(width: isHighlighted ? 10 : 8, height: isHighlighted ? 14 : 12)
                    .overlay(Capsule().stroke(Studio.accent, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .position(x: positionX, y: 4)
            }

            // Floating badge with timestamp and pitch/loudness reading
            if let labelText {
                Text(labelText)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isGhost ? Studio.secondary : Studio.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Studio.surface.opacity(0.95))
                            .overlay(Capsule().stroke(isGhost ? Studio.line : Studio.accent.opacity(0.6), lineWidth: 1))
                            .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    )
                    .position(x: badgeX, y: 16)
            }
        }
        .allowsHitTesting(false)
    }
}

struct InteractiveGraphOverlay: View {
    let duration: Double
    let playbackTime: Double
    let isPlaying: Bool
    var points: [TimePoint]? = nil
    var unit: String? = nil
    var showBadge: Bool = true
    var onSeek: (Double) -> Void
    var onScrub: ((Double) -> Void)? = nil

    @State private var isDragging = false
    @State private var dragTime: Double? = nil
    @State private var isHovered = false
    @State private var hoverTime: Double? = nil

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = geometry.size.height
            let activeTime = dragTime ?? (isPlaying || playbackTime > 0.05 ? playbackTime : nil)
            let displayTime = activeTime ?? (isHovered ? hoverTime : nil)

            ZStack(alignment: .topLeading) {
                // Interactive hit area
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let clampedX = max(0, min(value.location.x, width))
                                let time = TimelineScale.time(for: clampedX, width: width, duration: duration)
                                dragTime = time
                                onScrub?(time)
                            }
                            .onEnded { value in
                                let clampedX = max(0, min(value.location.x, width))
                                let time = TimelineScale.time(for: clampedX, width: width, duration: duration)
                                isDragging = false
                                dragTime = nil
                                onSeek(time)
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            isHovered = true
                            let clampedX = max(0, min(location.x, width))
                            hoverTime = TimelineScale.time(for: clampedX, width: width, duration: duration)
                            #if os(macOS)
                            NSCursor.pointingHand.set()
                            #endif
                        case .ended:
                            isHovered = false
                            hoverTime = nil
                            #if os(macOS)
                            NSCursor.arrow.set()
                            #endif
                        }
                    }

                // If active or hovered, render the playhead
                if let targetTime = displayTime {
                    let clampedTime = max(0, min(targetTime, duration))
                    let x = TimelineScale.x(for: clampedTime, duration: duration, width: width)
                    let isCurrentActive = activeTime != nil
                    let label = showBadge ? makeBadgeLabel(for: clampedTime) : nil

                    PlayheadView(
                        positionX: x,
                        height: height,
                        width: width,
                        labelText: label,
                        isHighlighted: isDragging || isCurrentActive,
                        isGhost: !isCurrentActive && isHovered
                    )
                }
            }
        }
    }

    private func makeBadgeLabel(for time: Double) -> String {
        let timeStr = String(format: "%.1fs", time)
        guard let unit, let points, !points.isEmpty else {
            return timeStr
        }
        if let val = contourValue(at: time, in: points) {
            if unit == "Hz" {
                return "\(Int(round(val))) Hz · \(timeStr)"
            } else {
                return "\(String(format: "%.1f", val)) \(unit) · \(timeStr)"
            }
        } else if unit == "Hz" {
            return "pause · \(timeStr)"
        } else {
            return timeStr
        }
    }
}

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
        .accessibilityLabel("Recorded voice waveform")
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

struct LineChartView: View {
    let points: [TimePoint]
    let color: Color
    let range: ClosedRange<Double>
    var duration: Double? = nil

    var body: some View {
        Canvas { context, size in
            guard points.count > 1, let finalTime = duration ?? points.last?.time, finalTime > 0 else { return }
            var path = Path()
            var started = false
            for point in points {
                let x = TimelineScale.x(for: point.time, duration: finalTime, width: size.width)
                let normalized = (point.value - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.001)
                let y = size.height - CGFloat(max(0, min(1, normalized))) * size.height
                if started { path.addLine(to: CGPoint(x: x, y: y)) }
                else { path.move(to: CGPoint(x: x, y: y)); started = true }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

struct SpectrogramView: View {
    let data: SpectrogramData

    var body: some View {
        Canvas { context, size in
            guard data.columns > 0, data.rows > 0, data.decibels.count == data.columns * data.rows else { return }
            let cellWidth = size.width / CGFloat(data.columns)
            let cellHeight = size.height / CGFloat(data.rows)
            for column in 0..<data.columns {
                for row in 0..<data.rows {
                    let value = data.decibels[column * data.rows + row]
                    let intensity = max(0, min(1, (value + 70) / 65))
                    // A sequential luminance scale keeps energy legible without a rainbow palette.
                    let color = Color(red: 0.055 + pow(intensity, 2.2) * 0.81,
                                      green: 0.10 + intensity * 0.79,
                                      blue: 0.12 + intensity * 0.55)
                    let rect = CGRect(
                        x: CGFloat(column) * cellWidth,
                        y: size.height - CGFloat(row + 1) * cellHeight,
                        width: cellWidth + 0.5,
                        height: cellHeight + 0.5
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .accessibilityLabel("Voice spectrogram from low to high frequency")
    }
}

struct LiveMeterView: View {
    let level: Double

    var body: some View {
        GeometryReader { geometry in
            let normalized = max(0, min(1, (level + 60) / 60))
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(level > -3 ? Color.orange : Studio.accent)
                        .frame(width: geometry.size.width * normalized)
                }
        }
        .frame(height: 8)
        .accessibilityLabel("Live microphone level")
        .accessibilityValue("\(Int(level)) decibels full scale")
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
                    VStack { gridline; Spacer(); gridline; Spacer(); gridline }
                    if points.count > 1 {
                        LineChartView(points: points, color: color, range: range, duration: duration)
                    } else {
                        Text("Not enough voiced audio for a contour")
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
        .accessibilityValue(points.isEmpty ? "No measurable contour" : "\(points.count) measurements over \(String(format: "%.1f", duration)) seconds, displayed from \(label(range.lowerBound)) to \(label(range.upperBound))")
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
                    .overlay(alignment: .leading) { Rectangle().fill(Studio.accent.opacity(0.8)).frame(width: 1) }
                    .overlay(alignment: .trailing) { Rectangle().fill(Studio.accent.opacity(0.8)).frame(width: 1) }
                    .frame(width: max(width, 2))
                    .offset(x: x)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
