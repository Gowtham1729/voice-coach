import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

extension TakeView {
  func transcriptCard(_ take: PracticeSession) -> some View {
    let highlightedWordIndex = highlightedWordIndex(in: take)
    return VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        SectionEyebrow(text: "Words")
        Spacer()
        if let transcription = take.transcription {
          Text("\(transcription.words.count) words")
            .font(.caption)
            .foregroundStyle(Studio.secondary)
          copyTranscriptButton(transcription.text)
        }
      }

      if let transcription = take.transcription {
        TakeTranscriptPane(
          transcription: transcription,
          highlightedWordIndex: highlightedWordIndex,
          isPlaying: model.isPlaying,
          reduceMotion: reduceMotion
        ) { index, word in
          selectedWordIndex = selectedWordIndex == index ? nil : index
          model.seek(to: word.start)
        }
      } else {
        ContentUnavailableView(
          "Transcript Unavailable",
          systemImage: "text.badge.xmark",
          description: Text(
            model.transcriptionNotice
              ?? "This take has audio and analysis, but no transcript.")
        )
        .frame(maxWidth: .infinity, minHeight: 200)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
    .studioCard()
  }

  func copyTranscriptButton(_ text: String) -> some View {
    StudioQuietIconButton(
      systemImage: "doc.on.doc",
      help: isTranscriptCopied ? "Copied" : "Copy transcript",
      confirmed: isTranscriptCopied
    ) {
      copyTranscript(text)
    }
    .disabled(text.isEmpty)
    .task(id: isTranscriptCopied) {
      await clearCopiedFlag(isTranscriptCopied) { isTranscriptCopied = false }
    }
  }

  func stickyTransport(_ take: PracticeSession) -> some View {
    let hasWords = !(take.transcription?.words.isEmpty ?? true)
    return VStack(spacing: 0) {
      Rectangle()
        .fill(Studio.line)
        .frame(height: 1)

      TakePlaybackRow(
        take: take,
        large: true,
        spaceShortcut: true,
        highlightedRange: selectedRange(take),
        canStepPreviousWord: canStepWord(in: take, by: -1),
        canStepNextWord: canStepWord(in: take, by: 1),
        onPreviousWord: hasWords ? { stepWord(in: take, by: -1) } : nil,
        onNextWord: hasWords ? { stepWord(in: take, by: 1) } : nil,
        onSeek: { time in
          selectedWordIndex = nil
          model.seek(to: time, autoplay: true)
        },
        onScrub: { time in
          selectedWordIndex = nil
          model.seek(to: time)
        }
      )
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .frame(maxWidth: 1050)
      .frame(maxWidth: .infinity)
    }
    .background {
      if snapshot {
        Studio.surface
      } else {
        Rectangle()
          .fill(.ultraThinMaterial)
          .overlay(Studio.surface.opacity(0.72))
          .ignoresSafeArea(edges: .bottom)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Take timeline")
  }

  func analysisCard(_ take: PracticeSession) -> some View {
    let highlightedRange = selectedRange(take)
    return VStack(alignment: .leading, spacing: 16) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          SectionEyebrow(text: "Analysis")
          Spacer()
          plotPicker
          copyGraphButton(take)
        }

        VStack(alignment: .leading, spacing: 10) {
          HStack {
            SectionEyebrow(text: "Analysis")
            Spacer()
            copyGraphButton(take)
          }
          plotPicker
        }
      }

      ZStack {
        activePlot(take, highlightedRange: highlightedRange, interactive: true)
          .id(selectedPlot)
          .transition(.opacity)
      }
      .frame(height: 380)
      .clipped()
      .animation(quickMotion, value: selectedPlot)
    }
    .padding(18)
    .frame(maxWidth: .infinity, minHeight: 460, alignment: .topLeading)
    .studioCard()
  }

  var plotPicker: some View {
    Picker("Analysis plot", selection: $selectedPlot) {
      ForEach(AnalysisPlot.allCases) { plot in
        Text(plot.rawValue).tag(plot)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .tint(.primary)
    .frame(maxWidth: 280)
  }

  func copyGraphButton(_ take: PracticeSession) -> some View {
    StudioQuietIconButton(
      systemImage: "doc.on.doc",
      help: isGraphCopied ? "Copied" : "Copy graph as PNG",
      confirmed: isGraphCopied
    ) {
      copyAnalysisSnapshot(take)
    }
    .task(id: isGraphCopied) {
      await clearCopiedFlag(isGraphCopied) { isGraphCopied = false }
    }
  }

  @ViewBuilder
  func activePlot(
    _ take: PracticeSession, highlightedRange: ClosedRange<Double>?, interactive: Bool
  ) -> some View {
    let result = take.result
    let playbackTime = interactive ? model.playbackTime : 0
    let isPlaying = interactive && model.isPlaying
    let onSeek: ((Double) -> Void)? =
      interactive
      ? { time in
        selectedWordIndex = nil
        model.seek(to: time, autoplay: true)
      } : nil
    let onScrub: ((Double) -> Void)? =
      interactive
      ? { time in
        selectedWordIndex = nil
        model.seek(to: time)
      } : nil

    switch selectedPlot {
    case .pitch:
      LabeledLineChart(
        points: result.pitchContour,
        color: Studio.accent,
        range: pitchBounds(result),
        duration: result.metrics.duration,
        unit: "Hz",
        playbackTime: playbackTime,
        isPlaying: isPlaying,
        highlightedRange: highlightedRange,
        maxJumpSemitones: 4,
        onSeek: onSeek,
        onScrub: onScrub
      )
    case .loudness:
      LabeledLineChart(
        points: result.loudnessContour,
        color: Studio.accent,
        range: -60...0,
        duration: result.metrics.duration,
        unit: "dBFS",
        playbackTime: playbackTime,
        isPlaying: isPlaying,
        highlightedRange: highlightedRange,
        onSeek: onSeek,
        onScrub: onScrub
      )
    case .spectrum:
      ZStack {
        SpectrogramView(data: result.spectrogram)
          .clipShape(RoundedRectangle(cornerRadius: 6))
        TimeRangeHighlight(range: highlightedRange, duration: result.metrics.duration)
        if interactive {
          InteractiveGraphOverlay(
            duration: result.metrics.duration,
            playbackTime: model.playbackTime,
            isPlaying: model.isPlaying,
            onSeek: { time in
              selectedWordIndex = nil
              model.seek(to: time, autoplay: true)
            },
            onScrub: { time in
              selectedWordIndex = nil
              model.seek(to: time)
            }
          )
        }
      }
    }
  }
}
