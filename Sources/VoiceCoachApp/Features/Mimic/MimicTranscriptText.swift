import SwiftUI
import VoiceCoachCore

/// Inline links preserve a readable paragraph while giving each timed word a
/// keyboard-accessible target. The custom URL is handled locally by this view.
struct MimicTranscriptText: View {
  let transcription: TranscriptionResult
  let activeIndex: Int?
  let activeColor: Color
  /// Words that sounded different from the reference get one quiet mark (UX-1). No red or green.
  var markedIndices: Set<Int> = []
  let onSelect: (Int, TranscriptWord) -> Void

  var body: some View {
    Text(linkedWords)
      .environment(
        \.openURL,
        OpenURLAction { url in
          guard url.scheme == "voicecoach-word",
            let index = Int(url.lastPathComponent),
            transcription.words.indices.contains(index)
          else { return .systemAction }
          onSelect(index, transcription.words[index])
          return .handled
        }
      )
      .help("Play from this word")
  }

  private var linkedWords: AttributedString {
    guard !transcription.words.isEmpty else { return AttributedString(transcription.text) }
    var result = AttributedString()
    for (index, word) in transcription.words.enumerated() {
      if index > 0 { result += AttributedString(" ") }
      var part = AttributedString(word.word)
      part.link = URL(string: "voicecoach-word://select/\(index)")
      if activeIndex == index {
        part.foregroundColor = activeColor
      } else {
        part.foregroundColor = Studio.ink
      }
      if markedIndices.contains(index), let core = Self.letterRange(in: part) {
        // Mark the word itself, not its trailing comma or full stop.
        part[core].underlineStyle = Text.LineStyle(pattern: .dot, color: Studio.ink.opacity(0.75))
      }
      result += part
    }
    return result
  }

  /// From the first to the last letter or digit; nil when the word has none.
  private static func letterRange(in text: AttributedString) -> Range<AttributedString.Index>? {
    let characters = text.characters
    let isCore: (Character) -> Bool = { $0.isLetter || $0.isNumber }
    guard let first = characters.firstIndex(where: isCore),
      let last = characters.lastIndex(where: isCore)
    else { return nil }
    return first..<characters.index(after: last)
  }
}
