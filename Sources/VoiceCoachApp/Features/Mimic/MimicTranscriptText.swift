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
      if markedIndices.contains(index) {
        part.underlineStyle = Text.LineStyle(pattern: .dot, color: Studio.secondary)
      }
      result += part
    }
    return result
  }
}
