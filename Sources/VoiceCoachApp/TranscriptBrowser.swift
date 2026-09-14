import SwiftUI
import VoiceCoachCore

struct TakeTranscriptPane: View {
    let transcription: TranscriptionResult
    let highlightedWordIndex: Int?
    let isPlaying: Bool
    let reduceMotion: Bool
    let onSelectWord: (Int, TranscriptWord) -> Void

    @Environment(\.studioSnapshot) private var snapshot

    private let paneHeight: CGFloat = 280

    var body: some View {
        wordBrowser
            .frame(height: paneHeight, alignment: .topLeading)
            .clipped()
            .accessibilityLabel("Word timings")
    }

    @ViewBuilder
    private var wordBrowser: some View {
        let words = Array(transcription.words.enumerated())
        if snapshot {
            wordGrid(entries: Array(words.prefix(36)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    wordGrid(entries: words)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: highlightedWordIndex) { _, index in
                    guard let index, isPlaying else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    private func wordGrid(entries: [(offset: Int, element: TranscriptWord)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(entries, id: \.offset) { index, word in
                WordTimingChip(
                    word: word,
                    isHighlighted: highlightedWordIndex == index,
                    isPlaying: isPlaying,
                    reduceMotion: reduceMotion,
                    action: { onSelectWord(index, word) }
                )
                .id(index)
            }
        }
    }
}

private struct WordTimingChip: View {
    let word: TranscriptWord
    let isHighlighted: Bool
    let isPlaying: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.word).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text("\(vcNumber(word.start, 2))–\(vcNumber(word.end, 2))s")
                    .font(.system(size: 8, design: .monospaced)).foregroundStyle(Studio.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHighlighted ? Studio.accent.opacity(0.16) : Studio.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(isHighlighted ? Studio.accent : Studio.line))
            .scaleEffect(isHighlighted && isPlaying ? 1.015 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHighlighted)
        }
        .buttonStyle(.plain)
    }
}
