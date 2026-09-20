import SwiftUI

enum VoiceMetricCopy {
  static let pitchRange = "Pitch range"
  static let phraseFade = "Phrase fade"
  static let clarity = "Clarity"
  static let pauses = "Pauses"
}

struct InspectorMetricCard: View {
  let title: String
  let value: String
  let unit: String
  var detail: String? = nil
  let symbol: String

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(title, systemImage: symbol)
        .font(.caption)
        .foregroundStyle(Studio.secondary)
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(value)
          .font(.title2.weight(.semibold))
          .foregroundStyle(.primary)
          .monospacedDigit()
          .contentTransition(.numericText())
        Text(unit)
          .font(.caption)
          .foregroundStyle(Studio.secondary)
      }
      if let detail {
        Text(detail)
          .font(.caption2)
          .foregroundStyle(Studio.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .animation(.smooth(duration: 0.22), value: value)
  }
}
