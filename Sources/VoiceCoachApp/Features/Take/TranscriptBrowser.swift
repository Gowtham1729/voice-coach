import SwiftUI
import VoiceCoachCore

/// The take's transcript as wrapping text. Each word is clickable and plays from there;
/// the word being played or selected is highlighted.
struct TakeTranscriptPane: View {
  let transcription: TranscriptionResult
  let highlightedWordIndex: Int?
  let isPlaying: Bool
  let reduceMotion: Bool
  let onSelectWord: (Int, TranscriptWord) -> Void

  private let maxHeight: CGFloat = 220

  var body: some View {
    // Short transcripts take only the room they need; long ones scroll.
    ViewThatFits(in: .vertical) {
      text
      ScrollView { text }
    }
    .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .topLeading)
    .accessibilityLabel("Transcript")
  }

  private var text: some View {
    MimicTranscriptText(
      transcription: transcription,
      activeIndex: highlightedWordIndex,
      activeColor: Studio.accent,
      onSelect: onSelectWord
    )
    .font(.title3)
    .lineSpacing(6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
  }
}
