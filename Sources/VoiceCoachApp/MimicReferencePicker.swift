import SwiftUI

struct MimicReferencePicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @Binding var start: Double
    @Binding var end: Double
    @State private var viewportStart = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Reference", systemImage: "waveform")
                .font(.headline)

            if let draft = model.mimicDraft {
                HStack(spacing: 12) {
                    Text(draft.sourceName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Button("Change…") { model.chooseMimicReference() }
                        .disabled(model.mimicIsPreparing)
                }

                MimicTrimWaveform(peaks: draft.peaks, duration: draft.duration,
                                  viewportStart: viewportStart, viewportDuration: min(30, draft.duration),
                                  start: $start, end: $end)
                    .frame(height: 82)
                    .accessibilityLabel("Reference excerpt range")

                if draft.duration > 30 {
                    HStack(spacing: 12) {
                        Text("Browse clip")
                            .font(.caption.weight(.medium))
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
                                }
                            ), in: 0...(draft.duration - 30))
                            .accessibilityLabel("Browse reference clip")
                        }
                        Text("\(vcDuration(viewportStart))–\(vcDuration(viewportStart + 30)) of \(vcDuration(draft.duration))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Studio.secondary)
                    }
                }

                HStack(spacing: 16) {
                    trimButtons(label: "Start", value: start, canDecrease: start > 0.001, canIncrease: start + 1.001 < end,
                                decrease: { start = max(0, start - 0.1) }, increase: { start = min(end - 1, start + 0.1) })
                    Spacer()
                    Text("\((end - start).formatted(.number.precision(.fractionLength(1)))) s selected")
                    Spacer()
                    trimButtons(label: "End", value: end, canDecrease: end - 1.001 > start, canIncrease: end + 0.001 < draft.duration,
                                decrease: { end = max(start + 1, end - 0.1) }, increase: { end = min(draft.duration, end + 0.1) })
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Studio.secondary)

                HStack {
                    Button(model.isPlaying ? "Stop Preview" : "Play Excerpt") {
                        if model.isPlaying { model.stopPlayback() }
                        else { model.playMimicDraft(start: start, end: end) }
                    }
                    .disabled(end - start < 1)
                    Spacer()
                    Text("Drag either handle to trim. Aim for a short spoken passage.")
                        .font(.caption)
                        .foregroundStyle(Studio.secondary)
                }
            } else {
                Button {
                    model.chooseMimicReference()
                } label: {
                    Label("Import Audio or Video…", systemImage: "square.and.arrow.down")
                }
                .disabled(model.mimicIsPreparing)
                .studioGlassButton()
                Text("Choose one voice clip. You can select a short excerpt after importing.")
                    .font(.caption)
                    .foregroundStyle(Studio.secondary)
                if model.mimicIsPreparing {
                    ProgressView("Preparing audio on this Mac…")
                        .controlSize(.small)
                }
            }

            Text("The reference and every attempt are saved locally in this session.")
                .font(.caption)
                .foregroundStyle(Studio.secondary)
        }
        .padding(16)
        .desktopPanel()
        .onChange(of: model.mimicDraft?.id) { _, _ in viewportStart = 0 }
    }

    private func trimButtons(label: String, value: Double, canDecrease: Bool, canIncrease: Bool,
                             decrease: @escaping () -> Void, increase: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text("\(label) \(value.formatted(.number.precision(.fractionLength(1)))) s")
                .frame(minWidth: 68, alignment: .leading)
            if snapshot {
                Text("−  +")
            } else {
                Button(action: decrease) { Text("−").frame(width: 16) }
                    .disabled(!canDecrease)
                    .help("Move \(label.lowercased()) 0.1 seconds earlier")
                Button(action: increase) { Text("+").frame(width: 16) }
                    .disabled(!canIncrease)
                    .help("Move \(label.lowercased()) 0.1 seconds later")
            }
        }
        .buttonStyle(.borderless)
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
                    let last = min(peaks.count, Int(ceil(Double(peaks.count) * (viewportStart + visible) / duration)))
                    guard first < last else { return }
                    for index in first..<last {
                        let time = Double(index) / Double(peaks.count) * duration
                        let x = CGFloat((time - viewportStart) / visible) * size.width
                        let height = max(2, CGFloat(min(peaks[index], 1)) * size.height * 0.8)
                        let barWidth = max(1, size.width * CGFloat(duration / visible) / CGFloat(peaks.count) - 1)
                        let bar = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                        context.fill(Path(roundedRect: bar, cornerRadius: 1), with: .color(Studio.accent.opacity(x >= left && x <= right ? 0.95 : 0.32)))
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
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { value in
                let change = Double(value.translation.width / width) * viewportDuration
                if isStart {
                    if startDragOrigin == nil { startDragOrigin = start }
                    start = min(max(viewportStart, (startDragOrigin ?? start) + change), end - 1)
                } else {
                    if endDragOrigin == nil { endDragOrigin = end }
                    end = max(min(viewportStart + viewportDuration, (endDragOrigin ?? end) + change), start + 1)
                }
            }.onEnded { _ in
                if isStart { startDragOrigin = nil }
                else { endDragOrigin = nil }
            })
            .accessibilityLabel(isStart ? "Excerpt start" : "Excerpt end")
            .accessibilityValue("\((isStart ? start : end).formatted(.number.precision(.fractionLength(1)))) seconds")
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? 0.1 : -0.1
                if isStart { start = min(max(0, start + delta), end - 1) }
                else { end = max(min(duration, end + delta), start + 1) }
            }
    }
}
