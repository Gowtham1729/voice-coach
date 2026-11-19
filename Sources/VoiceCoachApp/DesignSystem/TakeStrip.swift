import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

/// The one place to choose a take: Take 1, Take 2… each with its date and time.
/// Previous/Next take (⌥← / ⌥→) in the Practice menu step through the same list.
struct TakeStrip: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot
  let session: CoachingSession

  var body: some View {
    let selected = model.selectedTakeID ?? session.latestTake?.id
    if snapshot {
      // ImageRenderer does not draw scroll views; lay the chips out flat.
      HStack(spacing: 6) {
        ForEach(Array(session.takes.enumerated()), id: \.element.id) { index, take in
          chip(index: index, take: take, isSelected: take.id == selected)
        }
      }
    } else {
      scrollingStrip(selected: selected)
    }
  }

  private func scrollingStrip(selected: UUID?) -> some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(Array(session.takes.enumerated()), id: \.element.id) { index, take in
            chip(index: index, take: take, isSelected: take.id == selected)
              .id(take.id)
          }
        }
        .padding(.vertical, 2)
      }
      .onAppear { if let selected { proxy.scrollTo(selected, anchor: .trailing) } }
      .onChange(of: selected) { _, id in
        if let id { proxy.scrollTo(id, anchor: .center) }
      }
    }
    .disabled(model.isRecording || model.isAnalyzing || model.mimicPhase != .ready)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Takes")
  }

  private func chip(index: Int, take: PracticeSession, isSelected: Bool) -> some View {
    Button {
      model.selectTake(take.id)
    } label: {
      VStack(alignment: .leading, spacing: 1) {
        Text("Take \(index + 1)")
          .font(.caption.weight(.semibold))
        Text(Self.dateText(take.createdAt))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(isSelected ? Studio.ink : Studio.secondary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        isSelected ? Studio.accent.opacity(0.16) : Studio.surface,
        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(isSelected ? Studio.accent.opacity(0.55) : Studio.line, lineWidth: 1)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help(for: take))
    .accessibilityLabel("Take \(index + 1) of \(session.takeCount), \(Self.dateText(take.createdAt))")
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  private func help(for take: PracticeSession) -> String {
    guard session.isMimic else { return take.takeSource.title }
    return (session.mimicAttemptStyles?[take.id] ?? .listenAndRepeat).title
  }

  static func dateText(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) {
      return date.formatted(date: .omitted, time: .shortened)
    }
    return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
  }
}
