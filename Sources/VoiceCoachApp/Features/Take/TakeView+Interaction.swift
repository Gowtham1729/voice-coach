import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

extension TakeView {
  func takeNumber(_ take: PracticeSession, in session: CoachingSession) -> Int {
    (session.takes.firstIndex(where: { $0.id == take.id }) ?? 0) + 1
  }

  func selectedRange(_ take: PracticeSession) -> ClosedRange<Double>? {
    guard let highlightedWordIndex = highlightedWordIndex(in: take),
      let words = take.transcription?.words,
      words.indices.contains(highlightedWordIndex)
    else { return nil }
    return words[highlightedWordIndex].start...words[highlightedWordIndex].end
  }

  func highlightedWordIndex(in take: PracticeSession) -> Int? {
    guard let words = take.transcription?.words, !words.isEmpty else { return selectedWordIndex }

    // While playing, follow the playhead so highlight keeps moving after a seek.
    if model.isPlaying {
      return wordIndexAtPlayhead(words: words, time: model.playbackTime)
    }

    if let selectedWordIndex, words.indices.contains(selectedWordIndex) {
      return selectedWordIndex
    }

    return wordIndexAtPlayhead(words: words, time: model.playbackTime)
  }

  func canStepWord(in take: PracticeSession, by delta: Int) -> Bool {
    guard let words = take.transcription?.words, !words.isEmpty else { return false }
    return steppedWordIndex(words: words, by: delta) != nil
  }

  func stepWord(in take: PracticeSession, by delta: Int) {
    // SwiftUI arrow keyboardShortcuts can deliver the same keypress twice in one turn.
    guard !isHandlingWordStep else { return }
    isHandlingWordStep = true
    defer { Task { @MainActor in isHandlingWordStep = false } }

    guard let words = take.transcription?.words, !words.isEmpty,
      let target = steppedWordIndex(words: words, by: delta)
    else { return }

    selectedWordIndex = target
    model.seek(to: words[target].start)
  }

  func steppedWordIndex(words: [TranscriptWord], by delta: Int) -> Int? {
    let target: Int
    if let current = wordIndexForStepping(words: words) {
      target = current + delta
    } else if delta > 0 {
      target = 0
    } else {
      return nil
    }
    guard words.indices.contains(target) else { return nil }
    return target
  }

  /// Prefer the locked selection so rapid ←/→ stay one word at a time; once
  /// playback leaves that word, fall back to the live playhead.
  func wordIndexForStepping(words: [TranscriptWord]) -> Int? {
    if let selectedWordIndex, words.indices.contains(selectedWordIndex) {
      let word = words[selectedWordIndex]
      if !model.isPlaying || model.playbackTime <= word.end + 0.02 {
        return selectedWordIndex
      }
    }
    return wordIndexAtPlayhead(words: words, time: model.playbackTime)
  }

  /// Half-open [start, end) avoids double-counting when adjacent words share a boundary.
  func wordIndexAtPlayhead(words: [TranscriptWord], time: TimeInterval) -> Int? {
    if let index = words.firstIndex(where: { $0.start <= time && time < $0.end }) {
      return index
    }
    if let last = words.indices.last,
      words[last].start <= time,
      time <= words[last].end
    {
      return last
    }
    return words.lastIndex(where: { $0.start <= time })
  }

  @ViewBuilder
  func wordStepShortcuts(for take: PracticeSession) -> some View {
    let hasWords = !(take.transcription?.words.isEmpty ?? true)
    if hasWords {
      ZStack {
        Button("Previous word") { stepWord(in: take, by: -1) }
          .keyboardShortcut(.leftArrow, modifiers: [])
        Button("Next word") { stepWord(in: take, by: 1) }
          .keyboardShortcut(.rightArrow, modifiers: [])
      }
      .opacity(0)
      .frame(width: 0, height: 0)
      .accessibilityHidden(true)
    }
  }

  var quickMotion: Animation? {
    StudioMotion.quick(reduceMotion: reduceMotion)
  }

  func clearCopiedFlag(_ isCopied: Bool, clear: @escaping () -> Void) async {
    guard isCopied else { return }
    try? await Task.sleep(for: .seconds(2))
    if !Task.isCancelled { clear() }
  }
}
