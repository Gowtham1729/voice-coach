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
    static let background = Color(red: 11 / 255, green: 15 / 255, blue: 16 / 255)
    static let sidebar = Color(red: 15 / 255, green: 20 / 255, blue: 24 / 255)
    static let inspector = Color(red: 13 / 255, green: 18 / 255, blue: 22 / 255)
    static let surface = Color(red: 22 / 255, green: 27 / 255, blue: 34 / 255)
    static let ink = Color.white
    static let secondary = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
    static let accent = Color(red: 0.69, green: 0.89, blue: 0.77)
    static let line = Color.white.opacity(0.08)
}

enum StudioMotion {
    static func spring(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78)
    }

    static func quick(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0)
    }

    static func page(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.34, extraBounce: 0)
    }
}

struct StudioButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let tint = destructive ? Color(red: 0.96, green: 0.48, blue: 0.39) : Studio.accent
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, prominent ? 16 : 12)
            .frame(height: 32)
            .foregroundStyle(prominent ? Studio.background : Studio.ink)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint)
                }
            }
            .modifier(ControlGlass(
                tint: prominent ? tint.opacity(0.35) : (destructive ? tint.opacity(0.22) : nil),
                opaque: reduceTransparency,
                cornerRadius: 7
            ))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(buttonOpacity(isPressed: configuration.isPressed))
            .animation(StudioMotion.spring(reduceMotion: reduceMotion), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func buttonOpacity(isPressed: Bool) -> Double {
        guard enabled else { return 0.4 }
        return isPressed ? 0.82 : 1
    }
}

/// Quiet bordered control for inspector stacks — continuous rect, translucent, not capsule candy.
struct StudioInspectorButtonStyle: ButtonStyle {
    enum Role { case neutral, accented, destructive }

    var role: Role = .neutral
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.studioSnapshot) private var snapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    private static let destructiveTint = Color(red: 0.96, green: 0.48, blue: 0.39)
    private static let destructiveForeground = Color(red: 0.96, green: 0.55, blue: 0.50)

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.horizontal, 10)
            .background {
                if snapshot || reduceTransparency {
                    shape.fill(Studio.surface.opacity(role == .accented ? 0.95 : 0.72))
                } else {
                    shape.fill(.regularMaterial)
                        .overlay { shape.fill(fillWash) }
                }
            }
            .overlay {
                shape.strokeBorder(strokeColor, lineWidth: 0.5)
            }
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(StudioMotion.quick(reduceMotion: reduceMotion), value: configuration.isPressed)
            .contentShape(shape)
    }

    private var fillWash: Color {
        switch role {
        case .accented: Studio.accent.opacity(0.10)
        case .neutral, .destructive: Studio.surface.opacity(0.28)
        }
    }

    private var foreground: Color {
        switch role {
        case .neutral: Studio.ink.opacity(0.92)
        case .accented: Studio.accent
        case .destructive: Self.destructiveForeground
        }
    }

    private var strokeColor: Color {
        switch role {
        case .neutral: Studio.line
        case .accented: Studio.accent.opacity(0.35)
        case .destructive: Self.destructiveTint.opacity(0.4)
        }
    }
}

/// Low-contrast header icon control for in-card utilities (copy, etc.).
struct StudioQuietIconButton: View {
    let systemImage: String
    var help: String
    var confirmed = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: confirmed ? "checkmark" : systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering || confirmed ? Studio.ink : Studio.secondary)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? Studio.line.opacity(1.2) : Color.clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(hovering ? Studio.line : Color.clear, lineWidth: 0.5)
                }
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(StudioMotion.quick(reduceMotion: reduceMotion), value: hovering)
        .animation(StudioMotion.quick(reduceMotion: reduceMotion), value: confirmed)
    }
}

/// Liquid Glass chrome for controls (nav layer). Not for content cards.
struct ControlGlass: ViewModifier {
    var tint: Color? = nil
    var opaque = false
    var cornerRadius: CGFloat? = nil
    @Environment(\.studioSnapshot) private var snapshot
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let glass = tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive()
        if opaque || snapshot || reduceTransparency {
            content.modifier(OpaqueControlChrome(cornerRadius: cornerRadius))
        } else if let cornerRadius {
            content.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.glassEffect(glass, in: .capsule)
        }
    }
}

private struct OpaqueControlChrome: ViewModifier {
    var cornerRadius: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let cornerRadius {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .background(Studio.surface, in: shape)
                .overlay(shape.stroke(Studio.secondary.opacity(0.38), lineWidth: 0.5))
        } else {
            content
                .background(Studio.surface, in: Capsule())
                .overlay(Capsule().stroke(Studio.secondary.opacity(0.38), lineWidth: 0.5))
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
