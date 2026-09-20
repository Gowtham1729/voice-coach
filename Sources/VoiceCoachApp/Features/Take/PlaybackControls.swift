import SwiftUI
import VoiceCoachCore

struct TakePlaybackRow<Trailing: View>: View {
  @EnvironmentObject private var model: AppModel
  let take: PracticeSession
  var large = false
  var spaceShortcut = false
  var waveformColor: Color = Studio.accent
  var highlightedRange: ClosedRange<Double>? = nil
  var canStepPreviousWord = false
  var canStepNextWord = false
  var onPreviousWord: (() -> Void)? = nil
  var onNextWord: (() -> Void)? = nil
  var onPlay: (() -> Void)? = nil
  var onSeek: ((Double) -> Void)? = nil
  var onScrub: ((Double) -> Void)? = nil
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    HStack(spacing: large ? 18 : 11) {
      if let onPreviousWord {
        wordStepButton(
          systemImage: "chevron.backward",
          help: "Previous word (←)",
          shortcut: .leftArrow,
          active: canStepPreviousWord,
          action: onPreviousWord
        )
      }

      playButton

      if let onNextWord {
        wordStepButton(
          systemImage: "chevron.forward",
          help: "Next word (→)",
          shortcut: .rightArrow,
          active: canStepNextWord,
          action: onNextWord
        )
      }

      VStack(spacing: 6) {
        InteractiveWaveformView(
          points: take.result.waveform,
          duration: take.result.metrics.duration,
          playbackTime: model.playbackTime,
          isPlaying: model.isPlaying,
          color: waveformColor,
          highlightedRange: highlightedRange,
          onSeek: { time in (onSeek ?? { model.seek(to: $0, autoplay: true) })(time) },
          onScrub: { time in (onScrub ?? { model.seek(to: $0) })(time) }
        )
        .frame(height: large ? 48 : 30)
        if large {
          HStack {
            Text(vcDuration(model.playbackTime))
            Spacer()
            Text(vcDuration(take.result.metrics.duration))
          }
          .font(.system(size: 9, design: .monospaced))
          .foregroundStyle(Studio.secondary)
        }
      }
      .frame(maxWidth: .infinity)

      trailing()
    }
  }

  private var playButton: some View {
    Button(action: { (onPlay ?? model.playCurrent)() }) {
      Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
        .font(.system(size: large ? 16 : 11, weight: .semibold))
        .frame(width: large ? 44 : 32, height: large ? 44 : 32)
        .contentShape(Circle())
    }
    .buttonBorderShape(.circle)
    .tint(.primary)
    .studioGlassButton()
    .help(spaceShortcut ? "Play or pause (Space)" : "Play or pause")
    .modifier(ConditionalKeyboardShortcut(enabled: spaceShortcut, key: .space))
  }

  private func wordStepButton(
    systemImage: String,
    help: String,
    shortcut: KeyEquivalent,
    active: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: large ? 13 : 10, weight: .semibold))
        .frame(width: large ? 36 : 28, height: large ? 36 : 28)
        .contentShape(Circle())
    }
    .buttonBorderShape(.circle)
    .tint(.primary)
    .studioGlassButton()
    .help(help)
    .opacity(active ? 1 : 0.38)
    .keyboardShortcut(shortcut, modifiers: [])
  }
}

extension TakePlaybackRow where Trailing == EmptyView {
  init(
    take: PracticeSession,
    large: Bool = false,
    spaceShortcut: Bool = false,
    waveformColor: Color = Studio.accent,
    highlightedRange: ClosedRange<Double>? = nil,
    canStepPreviousWord: Bool = false,
    canStepNextWord: Bool = false,
    onPreviousWord: (() -> Void)? = nil,
    onNextWord: (() -> Void)? = nil,
    onPlay: (() -> Void)? = nil,
    onSeek: ((Double) -> Void)? = nil,
    onScrub: ((Double) -> Void)? = nil
  ) {
    self.take = take
    self.large = large
    self.spaceShortcut = spaceShortcut
    self.waveformColor = waveformColor
    self.highlightedRange = highlightedRange
    self.canStepPreviousWord = canStepPreviousWord
    self.canStepNextWord = canStepNextWord
    self.onPreviousWord = onPreviousWord
    self.onNextWord = onNextWord
    self.onPlay = onPlay
    self.onSeek = onSeek
    self.onScrub = onScrub
    self.trailing = { EmptyView() }
  }
}

struct MimicComparePlaybackRow: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot
  let reference: PracticeSession
  let attempt: PracticeSession
  let comparison: MimicComparison

  private var activeTake: PracticeSession {
    model.mimicPlaybackSource == .reference ? reference : attempt
  }

  private var waveformColor: Color {
    model.mimicPlaybackSource == .reference ? .cyan : Studio.accent
  }

  private var highlightedRange: ClosedRange<Double>? {
    guard let index = model.mimicSelectedWord, comparison.pairs.indices.contains(index) else {
      return nil
    }
    let pair = comparison.pairs[index]
    let word = model.mimicPlaybackSource == .reference ? pair.reference : pair.attempt
    return word.start...word.end
  }

  private var hasWords: Bool { !comparison.pairs.isEmpty }

  var body: some View {
    TakePlaybackRow(
      take: activeTake,
      large: true,
      spaceShortcut: true,
      waveformColor: waveformColor,
      highlightedRange: highlightedRange,
      canStepPreviousWord: canStepWord(by: -1),
      canStepNextWord: canStepWord(by: 1),
      onPreviousWord: hasWords ? { stepWord(by: -1) } : nil,
      onNextWord: hasWords ? { stepWord(by: 1) } : nil,
      onPlay: { model.toggleMimicPlayback() },
      onSeek: { time in model.seekMimic(source: model.mimicPlaybackSource, to: time) },
      onScrub: { time in model.playbackTime = time }
    ) {
      listenModeControl
        .frame(width: 140)
    }
    .id("\(activeTake.id)-\(model.mimicPlaybackSource)")
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Compare timeline")
  }

  private var listenModeControl: some View {
    HStack(spacing: 0) {
      ForEach(MimicPlaybackSource.allCases) { source in
        listenModeChip(source)
      }
    }
    .padding(3)
    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 7))
    .disabled(!snapshot && (model.isAnalyzing || model.mimicPhase != .ready))
  }

  @ViewBuilder
  private func listenModeChip(_ source: MimicPlaybackSource) -> some View {
    let selected = model.mimicPlaybackSource == source
    let label = Text(source.title)
      .font(.caption.weight(selected ? .semibold : .regular))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
      .contentShape(Rectangle())

    if snapshot {
      label
        .foregroundStyle(selected ? Studio.ink : Studio.secondary)
        .background(
          selected ? Studio.accent.opacity(0.18) : Color.clear,
          in: RoundedRectangle(cornerRadius: 5))
    } else {
      Button {
        selectListenMode(source)
      } label: {
        label
      }
      .buttonStyle(.plain)
      .foregroundStyle(selected ? Studio.ink : Studio.secondary)
      .background(
        selected ? Studio.accent.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 5)
      )
      .help(source.help)
    }
  }

  private func selectListenMode(_ source: MimicPlaybackSource) {
    switch source {
    case .reference:
      model.playMimicReference()
    case .attempt:
      model.playMimicAttempt()
    }
  }

  private func canStepWord(by delta: Int) -> Bool {
    guard hasWords else { return false }
    if let current = model.mimicSelectedWord {
      return comparison.pairs.indices.contains(current + delta)
    }
    return true
  }

  private func stepWord(by delta: Int) {
    guard hasWords else { return }
    let next: Int
    if let current = model.mimicSelectedWord {
      next = current + delta
    } else {
      next = delta > 0 ? 0 : comparison.pairs.count - 1
    }
    guard comparison.pairs.indices.contains(next) else { return }
    model.mimicSelectedWord = next
    let pair = comparison.pairs[next]
    let word = model.mimicPlaybackSource == .reference ? pair.reference : pair.attempt
    model.seekMimic(source: model.mimicPlaybackSource, to: word.start)
  }
}

private struct ConditionalKeyboardShortcut: ViewModifier {
  let enabled: Bool
  let key: KeyEquivalent

  @ViewBuilder
  func body(content: Content) -> some View {
    if enabled {
      content.keyboardShortcut(key, modifiers: [])
    } else {
      content
    }
  }
}
