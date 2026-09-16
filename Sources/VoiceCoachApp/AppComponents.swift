import SwiftUI
import VoiceCoachCore

struct StudioPage<Content: View>: View {
    var maxWidth: CGFloat = 1500
    var horizontalPadding: CGFloat = 42
    @ViewBuilder let content: Content

    var body: some View {
        StudioScroll {
            content
                .frame(maxWidth: maxWidth, alignment: .topLeading)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

struct StudioCard: ViewModifier {
    var cornerRadius: CGFloat = 16
    var emphasized = false
    @Environment(\.studioSnapshot) private var snapshot
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let borderColor = emphasized ? Studio.accent.opacity(0.18) : Studio.line

        content
            .background {
                if snapshot || reduceTransparency {
                    shape.fill(Studio.surface.opacity(emphasized ? 1.0 : 0.82))
                } else {
                    shape.fill(.regularMaterial)
                        .overlay { shape.fill(Studio.surface.opacity(emphasized ? 0.30 : 0.16)) }
                }
            }
            .overlay(shape.stroke(borderColor, lineWidth: 0.5))
    }
}

extension View {
    func studioCard(cornerRadius: CGFloat = 16, emphasized: Bool = false) -> some View {
        modifier(StudioCard(cornerRadius: cornerRadius, emphasized: emphasized))
    }

    /// Content-layer panel used by the desktop shell (not Liquid Glass).
    func desktopPanel() -> some View {
        modifier(DesktopPanel())
    }

    func studioHoverLift() -> some View {
        modifier(StudioHoverLift())
    }
}

private struct DesktopPanel: ViewModifier {
    @Environment(\.studioSnapshot) private var snapshot
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        content
            .background {
                if snapshot || reduceTransparency {
                    shape.fill(Studio.surface)
                } else {
                    shape.fill(.regularMaterial)
                        .overlay { shape.fill(Studio.surface.opacity(0.16)) }
                }
            }
    }
}

struct StudioHoverLift: ViewModifier {
    @Environment(\.studioSnapshot) private var snapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(!snapshot && !reduceMotion && hovering ? 1.01 : 1)
            .brightness(!snapshot && hovering ? 0.02 : 0)
            .animation(StudioMotion.quick(reduceMotion: reduceMotion), value: hovering)
            .onHover { if !snapshot { hovering = $0 } }
    }
}

struct MiniSparkline: View {
    let points: [TimePoint]
    var color = Studio.accent

    var body: some View {
        Canvas { context, size in
            let values = points.map(\.value).filter(\.isFinite)
            guard points.count > 1, let low = values.min(), let high = values.max() else { return }
            var path = Path()
            for (index, point) in points.enumerated() {
                let x = CGFloat(index) / CGFloat(max(points.count - 1, 1)) * size.width
                let normalized = (point.value - low) / max(high - low, 0.001)
                let y = size.height - CGFloat(normalized) * max(size.height - 4, 1) - 2
                index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

struct TakePlaybackRow: View {
    @EnvironmentObject private var model: AppModel
    let take: PracticeSession
    var large = false
    var spaceShortcut = false
    var highlightedRange: ClosedRange<Double>? = nil
    var canStepPreviousWord = false
    var canStepNextWord = false
    var onPreviousWord: (() -> Void)? = nil
    var onNextWord: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: large ? 18 : 11) {
            if let onPreviousWord {
                wordStepButton(
                    systemImage: "chevron.backward",
                    help: "Previous word (←)",
                    shortcut: .leftArrow,
                    active: canStepPreviousWord,
                    action: onPreviousWord
                )
            }

            playButton

            if let onNextWord {
                wordStepButton(
                    systemImage: "chevron.forward",
                    help: "Next word (→)",
                    shortcut: .rightArrow,
                    active: canStepNextWord,
                    action: onNextWord
                )
            }

            VStack(spacing: 6) {
                InteractiveWaveformView(
                    points: take.result.waveform,
                    duration: take.result.metrics.duration,
                    playbackTime: model.playbackTime,
                    isPlaying: model.isPlaying,
                    highlightedRange: highlightedRange,
                    onSeek: { model.seek(to: $0, autoplay: true) },
                    onScrub: { model.seek(to: $0) }
                )
                .frame(height: large ? 48 : 30)
                if large {
                    HStack {
                        Text(vcDuration(model.playbackTime))
                        Spacer()
                        Text(vcDuration(take.result.metrics.duration))
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Studio.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            shortcutHint(wordShortcuts: onPreviousWord != nil || onNextWord != nil)
        }
    }

    private var playButton: some View {
        Button(action: model.playCurrent) {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: large ? 16 : 11, weight: .semibold))
                .frame(width: large ? 44 : 32, height: large ? 44 : 32)
                .contentShape(Circle())
        }
        .buttonBorderShape(.circle)
        .tint(.primary)
        .studioGlassButton()
        .help(spaceShortcut ? "Play or pause (Space)" : "Play or pause")
        .modifier(ConditionalKeyboardShortcut(enabled: spaceShortcut, key: .space))
    }

    @ViewBuilder
    private func shortcutHint(wordShortcuts: Bool) -> some View {
        if spaceShortcut || wordShortcuts {
            HStack(spacing: 6) {
                if wordShortcuts { Text("← →") }
                if spaceShortcut { Text("SPACE") }
            }
            .font(.system(size: 9, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(Studio.secondary)
        } else {
            Text("1×")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Studio.secondary)
        }
    }

    private func wordStepButton(
        systemImage: String,
        help: String,
        shortcut: KeyEquivalent,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: large ? 13 : 10, weight: .semibold))
                .frame(width: large ? 36 : 28, height: large ? 36 : 28)
                .contentShape(Circle())
        }
        .buttonBorderShape(.circle)
        .tint(.primary)
        .studioGlassButton()
        .help(help)
        .opacity(active ? 1 : 0.38)
        .keyboardShortcut(shortcut, modifiers: [])
    }
}

private struct ConditionalKeyboardShortcut: ViewModifier {
    let enabled: Bool
    let key: KeyEquivalent

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.keyboardShortcut(key, modifiers: [])
        } else {
            content
        }
    }
}

struct DeleteTakeDialog: ViewModifier {
    @Binding var takeID: UUID?
    var onDelete: (UUID) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete this take?",
            isPresented: Binding(
                get: { takeID != nil },
                set: { if !$0 { takeID = nil } }
            )
        ) {
            Button("Delete take", role: .destructive) {
                if let takeID {
                    onDelete(takeID)
                }
                takeID = nil
            }
            Button("Cancel", role: .cancel) { takeID = nil }
        } message: {
            Text("The recording and analysis for this take will be removed from the session.")
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(Studio.accent)
            Text(title).font(.system(size: 22, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(Studio.secondary).multilineTextAlignment(.center)
            Button(actionTitle, action: action).studioGlassButton(prominent: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
        .studioCard()
    }
}

func vcNumber(_ value: Double, _ decimals: Int = 1) -> String {
    value.formatted(.number.precision(.fractionLength(decimals)))
}

func vcOptional(_ value: Double?, _ decimals: Int = 1) -> String {
    value.map { vcNumber($0, decimals) } ?? "—"
}

func vcSigned(_ value: Double, _ decimals: Int = 1) -> String {
    (value >= 0 ? "+" : "") + vcNumber(value, decimals)
}

func vcDuration(_ seconds: Double) -> String {
    String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
}

func vcDate(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
}
