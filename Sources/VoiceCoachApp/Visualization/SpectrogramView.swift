import SwiftUI
import VoiceCoachCore

struct SpectrogramView: View {
  let data: SpectrogramData

  var body: some View {
    Canvas { context, size in
      guard data.columns > 0, data.rows > 0, data.decibels.count == data.columns * data.rows else {
        return
      }
      let cellWidth = size.width / CGFloat(data.columns)
      let cellHeight = size.height / CGFloat(data.rows)
      for column in 0..<data.columns {
        for row in 0..<data.rows {
          let value = data.decibels[column * data.rows + row]
          let intensity = max(0, min(1, (value + 70) / 65))
          // Magma-style sequential ramp: dark navy → indigo → magenta → amber → cream.
          // Warm peaks stay clear of the cool blue playhead / accent chrome.
          let color = Self.magmaColor(intensity: intensity)
          let rect = CGRect(
            x: CGFloat(column) * cellWidth,
            y: size.height - CGFloat(row + 1) * cellHeight,
            width: cellWidth + 0.5,
            height: cellHeight + 0.5
          )
          context.fill(Path(rect), with: .color(color))
        }
      }
    }
    .accessibilityLabel("Voice spectrogram from low to high frequency")
  }

  /// Perceptually sequential stops for dark Studio chrome.
  private static func magmaColor(intensity: Double) -> Color {
    let t = max(0, min(1, pow(intensity, 2.1)))
    // position, r, g, b
    let stops: [(Double, Double, Double, Double)] = [
      (0.00, 0.043, 0.051, 0.078),  // #0B0D14 near-black navy
      (0.25, 0.102, 0.102, 0.290),  // #1A1A4A deep indigo
      (0.50, 0.608, 0.176, 0.431),  // #9B2D6E magenta-violet
      (0.75, 0.941, 0.627, 0.376),  // #F0A060 warm amber
      (1.00, 0.973, 0.910, 0.784),  // #F8E8C8 soft cream
    ]
    let upper = stops.firstIndex { $0.0 >= t } ?? (stops.count - 1)
    let lower = max(0, upper - 1)
    let a = stops[lower]
    let b = stops[upper]
    let local = (t - a.0) / max(b.0 - a.0, 1e-9)
    return Color(
      red: a.1 + (b.1 - a.1) * local,
      green: a.2 + (b.2 - a.2) * local,
      blue: a.3 + (b.3 - a.3) * local
    )
  }
}
