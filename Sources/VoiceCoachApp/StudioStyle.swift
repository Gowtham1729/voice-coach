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
    static let background = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let inspector = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let ink = Color.primary
    static let secondary = Color.secondary
    static let accent = Color.accentColor
    static let line = Color.primary.opacity(0.10)
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
    @Environment(\.studioSnapshot) private var snapshot
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
                opaque: reduceTransparency || snapshot,
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

/// Prefer `.studioGlassButton()` over `.glass` / `.glassProminent` so snapshot proofs stay ImageRenderer-safe.
extension View {
    @ViewBuilder
    func studioGlassButton(prominent: Bool = false) -> some View {
        StudioGlassButtonHost(prominent: prominent, content: self)
    }
}

private struct StudioGlassButtonHost<Content: View>: View {
    var prominent: Bool
    var content: Content
    @Environment(\.studioSnapshot) private var snapshot
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if snapshot || reduceTransparency {
            content.buttonStyle(StudioButtonStyle(prominent: prominent))
        } else if prominent {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
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
