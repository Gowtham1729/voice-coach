import SwiftUI

struct DeleteTakeDialog: ViewModifier {
  @Binding var takeID: UUID?
  var onDelete: (UUID) -> Void

  func body(content: Content) -> some View {
    content.confirmationDialog(
      "Delete this recording?",
      isPresented: Binding(
        get: { takeID != nil },
        set: { if !$0 { takeID = nil } }
      )
    ) {
      Button("Delete recording", role: .destructive) {
        if let takeID {
          onDelete(takeID)
        }
        takeID = nil
      }
      Button("Cancel", role: .cancel) { takeID = nil }
    } message: {
      Text("The recording and analysis will be removed. Other takes and Mimic references stay.")
    }
  }
}

struct EmptyState: View {
  let icon: String
  let title: String
  let detail: String
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(Studio.accent)
      Text(title).font(.system(size: 22, weight: .medium))
      Text(detail).font(.system(size: 12)).foregroundStyle(Studio.secondary).multilineTextAlignment(
        .center)
      Button(actionTitle, action: action).studioGlassButton(prominent: true)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 72)
    .studioCard()
  }
}

func vcNumber(_ value: Double, _ decimals: Int = 1) -> String {
  value.formatted(.number.precision(.fractionLength(decimals)))
}

func vcOptional(_ value: Double?, _ decimals: Int = 1) -> String {
  value.map { vcNumber($0, decimals) } ?? "—"
}

func vcSigned(_ value: Double, _ decimals: Int = 1) -> String {
  (value >= 0 ? "+" : "") + vcNumber(value, decimals)
}

func vcDuration(_ seconds: Double) -> String {
  String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
}
