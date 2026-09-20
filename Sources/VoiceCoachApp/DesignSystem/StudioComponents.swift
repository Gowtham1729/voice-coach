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
