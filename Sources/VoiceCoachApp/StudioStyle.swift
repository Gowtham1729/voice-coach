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

struct StudioButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let tint = destructive ? Color(red: 0.96, green: 0.48, blue: 0.39) : Studio.accent
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, prominent ? 16 : 12)
            .frame(height: 32)
            .foregroundStyle(prominent ? Studio.background : Studio.ink)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(prominent ? tint : Studio.surface)
            }
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 7).stroke(Studio.secondary.opacity(0.38), lineWidth: 0.5)
                }
            }
            .opacity(buttonOpacity(isPressed: configuration.isPressed))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }

    private func buttonOpacity(isPressed: Bool) -> Double {
        guard enabled else { return 0.4 }
        return isPressed ? 0.72 : 1
    }
}

struct SectionEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold))
            .tracking(2).foregroundStyle(Studio.secondary)
    }
}
