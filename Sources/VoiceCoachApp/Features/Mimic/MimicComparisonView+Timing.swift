import SwiftUI
import VoiceCoachCore

extension MimicComparisonView {
  var timingLanes: some View {
    let pairs = comparison.pairs
    let selected =
      model.isPlaying
      ? (followedWordIndex ?? model.mimicSelectedWord ?? 0)
      : (model.mimicSelectedWord ?? 0)
    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .bottom, spacing: 6) {
        ForEach(pairs.indices, id: \.self) { index in
          let pair = pairs[index]
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
              Text(pair.word)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
              if abs(pauseDifference(at: index)) >= 0.12 {
                Image(systemName: "pause.circle.fill")
                  .font(.caption2)
                  .foregroundStyle(.orange)
                  .help(
                    "Pause before this word differs by \(Int((abs(pauseDifference(at: index)) * 1_000).rounded())) ms"
                  )
              }
            }
            .frame(width: 132, alignment: .leading)
            timingWord(
              index: index, source: .reference, duration: pair.reference.end - pair.reference.start,
              otherDuration: pair.attempt.end - pair.attempt.start, color: .cyan)
            timingWord(
              index: index, source: .attempt, duration: pair.attempt.end - pair.attempt.start,
              otherDuration: pair.reference.end - pair.reference.start, color: Studio.accent)
          }
          .padding(6)
          .background(
            selected == index ? Studio.accent.opacity(0.12) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
          )
          .overlay(alignment: .bottomLeading) {
            if model.isPlaying, followedWordIndex == index {
              Rectangle()
                .fill(model.mimicPlaybackSource == .reference ? .cyan : Studio.accent)
                .frame(width: 144 * playbackPositionInWord, height: 2)
            }
          }
          .id(index)
        }
      }
      .padding(.vertical, 8)
    }
  }

  func timingWord(
    index: Int, source: MimicPlaybackSource, duration: Double,
    otherDuration: Double, color: Color
  ) -> some View {
    let width = max(5, 80 * CGFloat(max(0, duration) / max(0.001, duration, otherDuration)))
    return Button {
      jump(to: index, source: source)
    } label: {
      HStack(spacing: 3) {
        RoundedRectangle(cornerRadius: 2)
          .fill(color)
          .frame(width: width, height: 10)
          .frame(width: 80, alignment: .leading)
        Text("\(Int((duration * 1_000).rounded()))")
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(Studio.secondary)
          .lineLimit(1)
      }
      .frame(width: 132, height: 20, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(
      "Play \(source == .reference ? "reference" : "your take") from \(comparison.pairs[index].word), \(Int((duration * 1_000).rounded())) milliseconds"
    )
    .accessibilityLabel(
      "\(comparison.pairs[index].word), \(source == .reference ? "reference" : "you"), \(Int((duration * 1_000).rounded())) milliseconds. Play from here."
    )
  }

  func pause(before index: Int, source: MimicPlaybackSource) -> Double {
    guard index > 0 else { return 0 }
    let current = comparison.pairs[index]
    let previous = comparison.pairs[index - 1]
    guard
      source == .reference
        ? current.referenceIndex == previous.referenceIndex + 1
        : current.attemptIndex == previous.attemptIndex + 1
    else { return 0 }
    let start = source == .reference ? current.reference.start : current.attempt.start
    let end = source == .reference ? previous.reference.end : previous.attempt.end
    return max(0, start - end)
  }

  func pauseDifference(at index: Int) -> Double {
    guard index > 0 else { return 0 }
    let current = comparison.pairs[index]
    let previous = comparison.pairs[index - 1]
    guard current.referenceIndex == previous.referenceIndex + 1,
      current.attemptIndex == previous.attemptIndex + 1
    else { return 0 }
    return pause(before: index, source: .attempt) - pause(before: index, source: .reference)
  }
}
