import SwiftUI

/// Pitch/Emphasis legend swatch that mirrors the chart’s dashed Reference vs solid You strokes.
struct MimicSeriesLegendItem: View {
  let title: String
  let color: Color
  let dashed: Bool

  var body: some View {
    HStack(spacing: 6) {
      Canvas { context, size in
        var path = Path()
        let y = size.height / 2
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(
          path,
          with: .color(color),
          style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [5, 4] : [])
        )
      }
      .frame(width: 18, height: 8)
      .accessibilityHidden(true)

      Text(title)
        .foregroundStyle(color)
    }
  }
}
