import SwiftUI
import VoiceCoachCore

#if os(macOS)
  import AppKit
#endif

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
              accentColor.opacity(isGhost ? 0.15 : 0.45),
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
              .overlay(
                Capsule().stroke(isGhost ? Studio.line : Studio.accent.opacity(0.6), lineWidth: 1)
              )
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
