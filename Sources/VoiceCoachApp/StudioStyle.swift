import SwiftUI

// Flatten AppKit-backed containers only for offscreen layout proofs. The shipped
// UI always uses native scrolling and Liquid Glass compositing.
private struct StudioSnapshotKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var studioSnapshot: Bool {
        get { self[StudioSnapshotKey.self] }
        set { self[StudioSnapshotKey.self] = newValue }
    }
}

struct StudioScroll<Content: View>: View {
    @Environment(\.studioSnapshot) private var snapshot
    @ViewBuilder let content: Content
    var body: some View {
        if snapshot { content.frame(maxHeight: .infinity, alignment: .top).clipped() }
        else { ScrollView { content } }
    }
}

enum Studio {
    static let background = Color(red: 0.035, green: 0.060, blue: 0.066)
    static let surface = Color(red: 0.067, green: 0.093, blue: 0.098)
    static let ink = Color(red: 0.92, green: 0.95, blue: 0.92)
    static let secondary = Color(red: 0.59, green: 0.67, blue: 0.65)
    static let accent = Color(red: 0.69, green: 0.89, blue: 0.77)
    static let line = Color.white.opacity(0.10)
}

struct StudioButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let tint = destructive ? Color(red: 0.96, green: 0.48, blue: 0.39) : Studio.accent
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, prominent ? 23 : 16)
            .frame(height: prominent ? 48 : 36)
            .foregroundStyle(prominent ? Studio.background : Studio.ink)
            .background {
                if prominent {
                    Capsule().fill(tint)
                }
            }
            .modifier(ControlGlass(tint: prominent ? tint.opacity(0.35) : nil, opaque: reduceTransparency))
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

struct ControlGlass: ViewModifier {
    let tint: Color?
    let opaque: Bool
    @Environment(\.studioSnapshot) private var snapshot
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if opaque || snapshot || reduceTransparency {
            content.background(Studio.surface, in: Capsule())
                .overlay(Capsule().stroke(Studio.secondary.opacity(0.5)))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.18)))
        }
    }
}

struct SectionEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold))
            .tracking(2).foregroundStyle(Studio.secondary)
    }
}

/// An abstract voice sculpture. Only the recording state responds to microphone energy.
struct VoiceSculpture: View {
    var recording: Bool
    var level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.studioSnapshot) private var snapshot

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !recording || reduceMotion || snapshot)) { timeline in
            let time = recording && !reduceMotion && !snapshot ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.38
                let energy = recording ? max(0, min(1, (level + 60) / 55)) : 0.2
                for band in 0..<52 {
                    let latitude = Double(band) / 51 * .pi
                    let ringRadius = sin(latitude) * radius
                    let y = cos(latitude) * radius * 0.91
                    var path = Path()
                    for step in 0...160 {
                        let angle = Double(step) / 160 * .pi * 2
                        let ripple = sin(angle * 3 + latitude * 5 + time * 1.4) * (5 + energy * 13)
                        let x = cos(angle) * (ringRadius + ripple)
                        let depth = sin(angle) * ringRadius * 0.28
                        let point = CGPoint(x: center.x + x, y: center.y + y + depth + sin(angle * 2 + latitude * 3 + time) * 9)
                        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    let opacity = 0.18 + sin(latitude) * 0.45
                    context.stroke(path, with: .linearGradient(
                        Gradient(colors: [Studio.accent.opacity(opacity * 0.3), Studio.accent.opacity(opacity), Color(red: 0.44, green: 0.71, blue: 0.68).opacity(opacity * 0.5)]),
                        startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)
                    ), lineWidth: 0.8)
                }
            }
        }
        .background {
            Circle().fill(Studio.accent.opacity(0.065)).blur(radius: 48).padding(45)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
