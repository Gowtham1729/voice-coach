import AppKit
import SwiftUI
import VoiceCoachCore

/// Fixed-size transcript prose that never participates in SwiftUI text layout.
///
/// Nested `ScrollView` + `Text(longString)` was hanging the review page for a minute-plus:
/// StudioPage's outer scroll measured the inner scroll's content, which forced CoreText
/// `StyledTextLayoutEngine` / `TASCIIEncoder` over the entire transcript on the main thread.
/// An AppKit text view reports only the proposed frame size back to SwiftUI.
struct TranscriptProseView: NSViewRepresentable {
    let text: String

    final class Coordinator {
        var lastText: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView()
        textView.isEditable = false
        textView.isRichText = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = Self.inkColor
        textView.insertionPointColor = NSColor(red: 0.69, green: 0.89, blue: 0.77, alpha: 1)
        textView.font = Self.proseFont
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text
        context.coordinator.lastText = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if context.coordinator.lastText != text {
            textView.string = text
            context.coordinator.lastText = text
        }
        textView.textColor = Self.inkColor
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? 500,
            height: proposal.height ?? 150
        )
    }

    private static var inkColor: NSColor {
        NSColor(red: 0.92, green: 0.95, blue: 0.92, alpha: 1)
    }

    private static var proseFont: NSFont {
        let base = NSFont.systemFont(ofSize: 20)
        if let serif = base.fontDescriptor.withDesign(.serif) {
            return NSFont(descriptor: serif, size: 20) ?? base
        }
        return base
    }
}

struct ReviewTranscriptPane: View {
    let transcription: TranscriptionResult
    let highlightedWordIndex: Int?
    let isPlaying: Bool
    let reduceMotion: Bool
    let onSelectWord: (Int, TranscriptWord) -> Void

    @Environment(\.studioSnapshot) private var snapshot

    private let proseHeight: CGFloat = 150
    private let paneHeight: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            prose
            wordBrowser
        }
        .frame(height: paneHeight, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private var prose: some View {
        if snapshot {
            Text(transcription.text)
                .font(.system(size: 20, weight: .regular, design: .serif))
                .lineSpacing(5)
                .lineLimit(6)
                .frame(maxWidth: .infinity, maxHeight: proseHeight, alignment: .topLeading)
                .clipped()
        } else {
            TranscriptProseView(text: transcription.text)
                .frame(maxWidth: .infinity)
                .frame(height: proseHeight)
                .accessibilityLabel("Transcript")
                .accessibilityValue(transcription.text)
        }
    }

    @ViewBuilder
    private var wordBrowser: some View {
        let words = Array(transcription.words.enumerated())
        if snapshot {
            // Offscreen proofs flatten scrolling; keep a bounded sample so layout stays finite.
            wordGrid(entries: Array(words.prefix(36)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        } else {
            // Only the word chips scroll in SwiftUI. Concrete height keeps laziness intact
            // even when this pane sits inside StudioPage's outer ScrollView.
            ScrollView {
                wordGrid(entries: words)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func wordGrid(entries: [(offset: Int, element: TranscriptWord)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(entries, id: \.offset) { index, word in
                WordTimingChip(
                    word: word,
                    isHighlighted: highlightedWordIndex == index,
                    isPlaying: isPlaying,
                    reduceMotion: reduceMotion
                ) {
                    onSelectWord(index, word)
                }
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
