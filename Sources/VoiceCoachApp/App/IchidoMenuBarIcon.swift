import AppKit
import SwiftUI

/// The app's sound ribbon, simplified to three strokes for an 18-point template image.
/// Geometry follows scripts/generate-app-icon.swift; no white app-icon tile at this size.
@MainActor
enum IchidoMenuBarIcon {
  static let idle = makeImage(recording: false, ready: false)
  static let recording = makeImage(recording: true, ready: false)
  static let ready = makeImage(recording: false, ready: true)

  private static func makeImage(recording: Bool, ready: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
      NSColor.black.setStroke()
      for stripe in -1...1 {
        let path = NSBezierPath()
        path.lineWidth = 1.1
        path.lineCapStyle = .round
        for sample in 0...80 {
          let t = CGFloat(sample) / 80
          let envelope = pow(max(sin(.pi * t), 0), 0.8)
          let y = 420 + 180 * t + 90 * envelope * sin(4 * .pi * t - 0.36)
          let offset = CGFloat(stripe) * 1.7 * pow(max(sin(.pi * t), 0), 0.65)
          let point = NSPoint(x: 1 + 19 * t, y: 3 + (y - 340) * 0.027 + offset)
          if sample == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.stroke()
      }
      if recording {
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 17, y: 1, width: 4, height: 4)).fill()
      } else if ready {
        let check = NSBezierPath()
        check.lineWidth = 1.5
        check.lineCapStyle = .round
        check.move(to: NSPoint(x: 16, y: 3))
        check.line(to: NSPoint(x: 18, y: 1))
        check.line(to: NSPoint(x: 21, y: 5))
        check.stroke()
      }
      return true
    }
    image.isTemplate = true
    return image
  }
}

struct IchidoMenuBarLabel: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Image(nsImage: statusImage)
      .accessibilityLabel(statusLabel)
      .help(statusLabel)
  }

  private var statusImage: NSImage {
    if model.isCapturingMimicReference || model.isRecording { return IchidoMenuBarIcon.recording }
    if model.hasMenuBarReference && model.mimicDraft != nil { return IchidoMenuBarIcon.ready }
    return IchidoMenuBarIcon.idle
  }

  private var statusLabel: String {
    if model.isCapturingMimicReference { return "Ichido — capturing Mac audio" }
    if model.isRecording { return "Ichido — recording" }
    if model.hasMenuBarReference && model.mimicDraft != nil { return "Ichido — capture ready to review" }
    return "Ichido — quick practice"
  }
}
