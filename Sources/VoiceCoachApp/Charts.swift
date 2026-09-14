import SwiftUI
import VoiceCoachCore

struct WaveformView: View {
    let points: [WaveformPoint]
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
                let x = CGFloat(index) / CGFloat(max(points.count - 1, 1)) * size.width
                path.move(to: CGPoint(x: x, y: middle - CGFloat(point.maximum) * middle))
                path.addLine(to: CGPoint(x: x, y: middle - CGFloat(point.minimum) * middle))
            }
            context.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 1)
        }
        .accessibilityLabel("Recorded voice waveform")
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
                let x = CGFloat(point.time / finalTime) * size.width
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
                .fill(Color.white.opacity(0.12))
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
