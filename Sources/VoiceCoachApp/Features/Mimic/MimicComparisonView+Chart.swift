import SwiftUI
import VoiceCoachCore

extension MimicComparisonView {
  var chartContents: some View {
    VStack(alignment: .leading, spacing: 8) {
      if metric == .timing {
        timingLanes
      } else {
        contour
      }
      if metric != .timing { wordPicker }
    }
    .frame(minWidth: 590, alignment: .leading)
  }

  func followableChart(viewportWidth: CGFloat) -> some View {
    ScrollView(.horizontal) {
      chartContents
    }
    .scrollIndicators(.hidden)
    .scrollPosition($chartPosition)
    .onChange(of: model.playbackTime) { _, _ in
      guard followPlayback, model.isPlaying, let x = playbackX else { return }
      centerChart(on: x, viewportWidth: viewportWidth, animated: false)
    }
    .onChange(of: metric) { _, _ in
      centerChart(onWord: model.mimicSelectedWord ?? 0, viewportWidth: viewportWidth)
    }
    .onChange(of: model.mimicSelectedWord) { _, index in
      guard let index else { return }
      centerChart(onWord: index, viewportWidth: viewportWidth)
    }
    .onChange(of: followPlayback) { _, enabled in
      guard enabled, let x = playbackX else { return }
      centerChart(on: x, viewportWidth: viewportWidth)
    }
    .onAppear {
      guard metric == .timing else { return }
      centerChart(onWord: model.mimicSelectedWord ?? 0, viewportWidth: viewportWidth)
    }
    .overlay(alignment: .topLeading) {
      if followPlayback,
        model.isPlaying || model.playbackTime > 0,
        let x = playbackX
      {
        followPlayhead
          .offset(x: playheadViewportX(for: x, viewportWidth: viewportWidth))
      }
    }
  }

  var chartHeight: CGFloat { metric == .timing ? 105 : 280 }
  var chartCellWidth: CGFloat { metric == .timing ? 150 : 74 }

  var chartContentWidth: CGFloat {
    let count = CGFloat(comparison.pairs.count)
    switch metric {
    case .timing:
      return max(590, count * 150 - 6)
    case .pitch, .emphasis:
      return max(630, count * 74)
    }
  }

  /// Centers `contentX` when possible; at the ends, scroll stops and the playhead slides.
  func clampedScrollOffset(centering contentX: CGFloat, viewportWidth: CGFloat) -> CGFloat {
    let maxScroll = max(0, chartContentWidth - viewportWidth)
    return min(max(0, contentX - viewportWidth / 2), maxScroll)
  }

  func centerChart(on contentX: CGFloat, viewportWidth: CGFloat, animated: Bool = true) {
    let offset = clampedScrollOffset(centering: contentX, viewportWidth: viewportWidth)
    guard animated else {
      var transaction = Transaction()
      transaction.animation = nil
      withTransaction(transaction) { chartPosition.scrollTo(x: offset) }
      return
    }
    chartPosition.scrollTo(x: offset)
  }

  func centerChart(onWord index: Int, viewportWidth: CGFloat) {
    guard comparison.pairs.indices.contains(index) else { return }
    centerChart(
      on: CGFloat(index) * chartCellWidth + chartCellWidth / 2, viewportWidth: viewportWidth)
  }

  func playheadViewportX(for contentX: CGFloat, viewportWidth: CGFloat) -> CGFloat {
    contentX - clampedScrollOffset(centering: contentX, viewportWidth: viewportWidth) - 0.75
  }

  var followPlayhead: some View {
    Rectangle()
      .fill(Studio.ink.opacity(0.85))
      .frame(width: 1.5, height: metric == .timing ? 100 : 238)
      .overlay(alignment: .top) {
        Circle()
          .fill(model.mimicPlaybackSource == .reference ? .cyan : Studio.accent)
          .frame(width: 8, height: 8)
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }

  var chartCaption: String {
    switch metric {
    case .pitch: "Relative pitch contour · semitones aligned by matched words"
    case .timing:
      "Word durations (ms) · longer bar fills each pair · orange marks changed pauses · click a row to play"
    case .emphasis: "Relative word energy · dB"
    }
  }

  var followedWordIndex: Int? {
    guard model.isPlaying || model.playbackTime > 0 else { return nil }
    let time = model.playbackTime
    let source = model.mimicPlaybackSource
    return comparison.pairs.indices.last(where: {
      let word =
        source == .reference ? comparison.pairs[$0].reference : comparison.pairs[$0].attempt
      return word.start <= time
    })
  }

  var playbackPositionInWord: CGFloat {
    guard let index = followedWordIndex else { return 0 }
    let word =
      model.mimicPlaybackSource == .reference
      ? comparison.pairs[index].reference : comparison.pairs[index].attempt
    return CGFloat(
      max(0, min(1, (model.playbackTime - word.start) / max(0.001, word.end - word.start))))
  }

  var playbackX: CGFloat? {
    guard let index = followedWordIndex else { return nil }
    let source = model.mimicPlaybackSource
    let word =
      source == .reference ? comparison.pairs[index].reference : comparison.pairs[index].attempt
    let cell = chartCellWidth
    let inset: CGFloat = metric == .timing ? 6 : 0
    let spokenWidth: CGFloat = metric == .timing ? 132 : 74
    let wordEndX = CGFloat(index) * cell + inset + spokenWidth
    if comparison.pairs.indices.contains(index + 1) {
      let next =
        source == .reference
        ? comparison.pairs[index + 1].reference : comparison.pairs[index + 1].attempt
      if next.start > word.end, model.playbackTime > word.end {
        let pauseFraction = CGFloat(
          min(1, (model.playbackTime - word.end) / (next.start - word.end)))
        let nextStartX = CGFloat(index + 1) * cell + inset
        return wordEndX + pauseFraction * (nextStartX - wordEndX)
      }
    }
    return CGFloat(index) * cell + inset + playbackPositionInWord * spokenWidth
  }

  func jump(to index: Int, source: MimicPlaybackSource) {
    guard comparison.pairs.indices.contains(index) else { return }
    model.mimicSelectedWord = index
    let word =
      source == .reference ? comparison.pairs[index].reference : comparison.pairs[index].attempt
    model.seekMimic(source: source, to: word.start)
  }

  func transcriptRow(
    _ label: String, transcription: TranscriptionResult?, color: Color,
    source: MimicPlaybackSource
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 18) {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .frame(width: 78, alignment: .leading)
      if let transcription {
        MimicTranscriptText(
          transcription: transcription,
          activeIndex: activeTranscriptIndex(in: transcription, source: source),
          activeColor: color
        ) { index, word in
          model.mimicSelectedWord = comparison.pairs.firstIndex(where: {
            source == .reference ? $0.referenceIndex == index : $0.attemptIndex == index
          })
          model.seekMimic(source: source, to: word.start)
        }
        .font(.body)
      } else {
        Text("Transcript unavailable")
          .foregroundStyle(Studio.secondary)
      }
    }
  }

  func activeTranscriptIndex(in transcription: TranscriptionResult, source: MimicPlaybackSource)
    -> Int?
  {
    guard model.isPlaying, model.mimicPlaybackSource == source else { return nil }
    return transcription.words.firstIndex(where: {
      model.playbackTime >= $0.start && model.playbackTime < $0.end
    })
  }

  var wordPicker: some View {
    HStack(spacing: 4) {
      ForEach(comparison.pairs.indices, id: \.self) { index in
        Button {
          jump(to: index, source: model.mimicPlaybackSource)
        } label: {
          Text(comparison.pairs[index].word)
            .lineLimit(1)
            .frame(width: 70)
            .padding(.vertical, 6)
            .background(
              model.mimicSelectedWord == index ? Studio.accent.opacity(0.22) : .clear,
              in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(
          "Play \(comparison.pairs[index].word) in \(model.mimicPlaybackSource == .reference ? "reference" : "your take")"
        )
        .id(index)
      }
    }
  }

  var contour: some View {
    let pairs = comparison.pairs
    let displayedMetric = metric
    let ref = reference
    let own = attempt
    let chartWidth = max(630, CGFloat(pairs.count) * 74)
    return Canvas { context, size in
      let cell: CGFloat = 74
      let middle = size.height / 2
      var axis = Path()
      axis.move(to: CGPoint(x: 0, y: middle))
      axis.addLine(to: CGPoint(x: size.width, y: middle))
      context.stroke(axis, with: .color(Studio.secondary.opacity(0.3)), lineWidth: 1)

      if displayedMetric == .pitch {
        for (take, isReference) in [(ref, true), (own, false)] {
          guard let median = take.result.metrics.medianPitchHz, median > 0 else { continue }
          let samples = take.result.acousticFrames.pitch
          for (index, pair) in pairs.enumerated() {
            let word = isReference ? pair.reference : pair.attempt
            let span = max(0.001, word.end - word.start)
            var path = Path()
            var lastTime: Double?
            for sample in samples
            where sample.time >= word.start && sample.time <= word.end && sample.value > 0 {
              let position = max(0, min(1, (sample.time - word.start) / span))
              let relative = 12 * log2(sample.value / median)
              let fraction = max(-1, min(1, relative / 8))
              let point = CGPoint(
                x: CGFloat(index) * cell + CGFloat(position) * cell,
                y: middle - CGFloat(fraction) * (middle - 15)
              )
              if let lastTime, sample.time - lastTime < 0.04 {
                path.addLine(to: point)
              } else {
                path.move(to: point)
              }
              lastTime = sample.time
            }
            context.stroke(
              path, with: .color(isReference ? .cyan : Studio.accent),
              style: StrokeStyle(lineWidth: 2, dash: isReference ? [5, 4] : []))
          }
        }
        return
      }

      func points(_ reference: Bool) -> [(CGPoint, Int)] {
        pairs.enumerated().compactMap { index, pair in
          let value = reference ? pair.referenceEnergy : pair.attemptEnergy
          guard let value, value.isFinite else { return nil }
          let fraction = max(-1.0, min(1.0, value / 12))
          return (
            CGPoint(
              x: CGFloat(index) * cell + cell / 2, y: middle - CGFloat(fraction) * (middle - 15)),
            index
          )
        }
      }

      for isReference in [true, false] {
        let samples = points(isReference)
        var path = Path()
        var lastIndex: Int?
        for (point, index) in samples {
          if lastIndex == index - 1 { path.addLine(to: point) } else { path.move(to: point) }
          lastIndex = index
          context.fill(
            Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
            with: .color(isReference ? .cyan : Studio.accent))
        }
        context.stroke(
          path, with: .color(isReference ? .cyan : Studio.accent),
          style: StrokeStyle(lineWidth: 2, dash: isReference ? [5, 4] : []))
      }
    }
    .frame(width: chartWidth, height: 238)
    .contentShape(Rectangle())
    .onTapGesture { location in
      let index = Int(location.x / 74)
      jump(to: index, source: model.mimicPlaybackSource)
    }
    .accessibilityLabel(
      "\(metric.rawValue) comparison of \(pairs.count) matched words. Choose a word below to play it."
    )
    .overlay(alignment: .topLeading) {
      if !followPlayback, let x = playbackX {
        Canvas { context, size in
          var path = Path()
          path.move(to: CGPoint(x: x, y: 10))
          path.addLine(to: CGPoint(x: x, y: size.height - 4))
          context.stroke(path, with: .color(Studio.ink.opacity(0.8)), lineWidth: 1.5)
          context.fill(
            Path(ellipseIn: CGRect(x: x - 4, y: 2, width: 8, height: 8)),
            with: .color(model.mimicPlaybackSource == .reference ? .cyan : Studio.accent))
        }
        .frame(width: chartWidth, height: 238)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
    }
  }
}
