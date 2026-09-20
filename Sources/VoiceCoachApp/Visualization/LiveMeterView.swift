import SwiftUI

struct LiveMeterView: View {
  let level: Double

  var body: some View {
    GeometryReader { geometry in
      let normalized = max(0, min(1, (level + 60) / 60))
      Capsule()
        .fill(Color.primary.opacity(0.12))
        .overlay(alignment: .leading) {
          Capsule()
            .fill(level > -3 ? Color.orange : Studio.accent)
            .frame(width: geometry.size.width * normalized)
        }
    }
    .frame(height: 8)
    .accessibilityLabel("Live microphone level")
    .accessibilityValue("\(Int(level)) decibels full scale")
  }
}
