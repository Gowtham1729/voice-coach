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

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [Studio.surface.opacity(emphasized ? 0.96 : 0.76), Studio.surface.opacity(0.54)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(emphasized ? Studio.accent.opacity(0.30) : Studio.line)
            )
    }
}

extension View {
    func studioCard(cornerRadius: CGFloat = 16, emphasized: Bool = false) -> some View {
        modifier(StudioCard(cornerRadius: cornerRadius, emphasized: emphasized))
    }
}

struct BackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.left")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Studio.secondary)
        }
        .buttonStyle(.plain)
    }
}

struct StudioSearchField: View {
    @Binding var text: String
    @Environment(\.studioSnapshot) private var snapshot
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isFocused ? Studio.accent : Studio.secondary)

            if snapshot {
                Text("Search sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(Studio.secondary)
            } else {
                TextField("Search sessions", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($isFocused)
                    .focusEffectDisabled()
                    .accessibilityLabel("Search sessions")
            }
        }
        .padding(.horizontal, 15)
        .frame(width: 300, height: 48, alignment: .leading)
        .background(Studio.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isFocused ? Studio.accent.opacity(0.7) : Studio.line, lineWidth: isFocused ? 1.5 : 1)
        )
        .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

struct PrivacyFooter: View {
    @AppStorage("voiceCoach.keepWindowPrivate") private var privacyReminder = true

    var body: some View {
        Group {
            if privacyReminder {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "checkmark.shield").foregroundStyle(Studio.accent)
                    Text("Only on your Mac. Coaching measurements, not a medical assessment.\nUse the same microphone setup when comparing takes.")
                        .lineSpacing(3)
                    Spacer()
                    Text("SPEAK. LISTEN. GROW.")
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(2)
                }
                .font(.system(size: 10))
                .foregroundStyle(Studio.secondary)
                .padding(.top, 22)
            }
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let unit: String
    let detail: String
    var accent = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(Studio.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 29, weight: .regular))
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundStyle(accent ? Studio.accent : Studio.ink)
                Text(unit).font(.system(size: 10)).foregroundStyle(Studio.secondary)
            }
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(Studio.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct DeltaLabel: View {
    let value: Double
    let unit: String
    let positiveIsGood: Bool

    var body: some View {
        let improved = positiveIsGood ? value >= 0 : value <= 0
        Label("\(value >= 0 ? "+" : "")\(vcNumber(value, 1)) \(unit)", systemImage: improved ? "arrow.up" : "arrow.down")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(improved ? Studio.accent : Studio.secondary)
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

    var body: some View {
        HStack(spacing: large ? 18 : 11) {
            Button(action: model.playCurrent) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: large ? 18 : 11, weight: .semibold))
                    .foregroundStyle(Studio.background)
                    .frame(width: large ? 54 : 32, height: large ? 54 : 32)
                    .background(Studio.accent, in: Circle())
            }
            .buttonStyle(.plain)
            VStack(spacing: 6) {
                InteractiveWaveformView(
                    points: take.result.waveform,
                    duration: take.result.metrics.duration,
                    playbackTime: model.playbackTime,
                    isPlaying: model.isPlaying,
                    highlightedRange: nil,
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
            Text("1×").font(.system(size: 10, design: .monospaced)).foregroundStyle(Studio.secondary)
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
            Button(actionTitle, action: action).buttonStyle(StudioButtonStyle(prominent: true))
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
