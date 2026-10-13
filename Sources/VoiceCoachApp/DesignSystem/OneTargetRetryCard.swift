import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

/// The single actionable coaching cue for the selected take.
struct OneTargetRetryCard: View {
  @EnvironmentObject private var model: AppModel

  let session: CoachingSession
  let take: PracticeSession

  private var isReference: Bool { session.isMimic }

  private func line(for plan: CoachingPlan) -> String {
    guard take.transcription != nil else { return OneTargetRetryStrings.noTranscript }
    if isReference {
      if let evaluation = plan.retryEvaluation {
        if evaluation.verdict == .neutral {
          return OneTargetRetryStrings.neutralRetryLine(word: evaluation.target.word)
        }
        if evaluation.verdict == .otherWay || evaluation.verdict == .unreliable {
          return evaluation.cueCopy
        }
        return evaluation.verdictCopy ?? evaluation.cueCopy
      }
      guard let focus = plan.focus else { return OneTargetRetryStrings.noReferenceAlignment }
      switch focus.kind {
      case .pitch: return OneTargetRetryStrings.pitchCue(word: focus.word)
      case .loudness: return OneTargetRetryStrings.loudnessCue(phrase: focus.word)
      case .timing: return OneTargetRetryStrings.timingCue(phrase: focus.word)
      }
    }
    return plan.plainTakeCue?.cueText ?? OneTargetRetryStrings.noLongPauses
  }

  var body: some View {
    let plan = model.coachingPlan(for: take, in: session)
    let focus = plan.focus
    let evaluation = plan.retryEvaluation
    let hasCue = take.transcription != nil && (isReference ? focus != nil : plan.plainTakeCue != nil)
    let focusPair: MimicWordPair? = {
      guard let focus, let reference = session.mimicReference?.take else { return nil }
      return MimicComparison.compare(reference: reference, attempt: take).pairs.first {
        $0.referenceIndex == focus.referenceWordIndex
      }
    }()
    Group {
      if model.skippedRetryCardTakeIDs.contains(take.id) {
        HStack(spacing: 12) {
          Text(OneTargetRetryStrings.skipped)
            .foregroundStyle(Studio.secondary)
          Button(OneTargetRetryStrings.show) { model.showRetryCard(for: take.id) }
            .buttonStyle(.plain)
            .foregroundStyle(Studio.accent)
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
      } else if !model.dismissedRetryCardTakeIDs.contains(take.id) {
        VStack(alignment: .leading, spacing: 14) {
          Text(line(for: plan))
            .font(.body.weight(.medium))
            .foregroundStyle(Studio.ink)
            .fixedSize(horizontal: false, vertical: true)

          if hasCue {
            if isReference, let focus {
              HStack(spacing: 8) {
                if let spans = evaluation?.neutralReplaySpans {
                  if let previous = spans.previous {
                    Button(OneTargetRetryStrings.previousTake) {
                      model.playPreviousFocusSegment(
                        takeID: spans.previousTakeID, range: previous)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isRecording || model.isAnalyzing)
                  } else {
                    Button(OneTargetRetryStrings.previousTake) {}
                      .buttonStyle(.bordered)
                      .disabled(true)
                  }
                  if let current = spans.current {
                    replayChip(OneTargetRetryStrings.thisTake, source: .attempt,
                      span: current, focusWordRange: current)
                  } else {
                    Button(OneTargetRetryStrings.thisTake) {}
                      .buttonStyle(.bordered)
                      .disabled(true)
                  }
                  replayChip(OneTargetRetryStrings.referenceChip, source: .reference,
                    span: spans.reference, focusWordRange: spans.reference)
                } else {
                  replayChip(OneTargetRetryStrings.yourTake, source: .attempt,
                    span: evaluation?.newTakeRange ?? focus.takeRange,
                    focusWordRange: focusPair.map { $0.attempt.start...$0.attempt.end }
                      ?? focus.takeRange)
                  replayChip(OneTargetRetryStrings.referenceChip, source: .reference,
                    span: focus.referenceRange,
                    focusWordRange: focusPair.map { $0.reference.start...$0.reference.end }
                      ?? focus.referenceRange)
                }
              }
            } else if let pause = plan.plainTakeCue {
              Button("Play") {
                model.playFocusSegment(
                  source: .attempt, range: pause.cueSpanRange,
                  focusWordRange: pause.pauseRange.upperBound...pause.cueSpanRange.upperBound)
              }
              .buttonStyle(.plain)
              .foregroundStyle(Studio.accent)
              .accessibilityLabel("Play pause before \(pause.followingWord)")
            }
          }

          HStack(spacing: 16) {
            if isReference && hasCue && evaluation?.verdict != .closeEnough {
              Button(OneTargetRetryStrings.tryAgain) {
                model.tryAgain(take: take, in: session)
              }
              .studioGlassButton(prominent: true)
              .disabled(model.isRecording || model.isAnalyzing || model.isPlaying)
            } else if isReference {
              Button(OneTargetRetryStrings.replayBoth) { model.replayBoth() }
                .studioGlassButton(prominent: true)
                .disabled(model.isRecording || model.isAnalyzing)
            } else if !hasCue {
              Button(OneTargetRetryStrings.addReference) {
                model.useCurrentRecordingAsMimicReference()
              }
              .buttonStyle(.bordered)
              .disabled(model.isRecording || model.isAnalyzing)
            }

            if hasCue && evaluation?.verdict != .closeEnough {
              Button(OneTargetRetryStrings.skip) { model.skipRetryCard(for: take.id) }
                .buttonStyle(.plain)
                .foregroundStyle(Studio.secondary)
              Button(OneTargetRetryStrings.thatWasOnPurpose) {
                model.dismissRetryCard(for: take.id)
              }
              .buttonStyle(.plain)
              .foregroundStyle(Studio.secondary)
            }
          }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
      }
    }
  }

  private func replayChip(
    _ title: String, source: MimicPlaybackSource, span: ClosedRange<Double>,
    focusWordRange: ClosedRange<Double>
  ) -> some View {
    Button(title) {
      model.playFocusSegment(
        source: source, range: span, focusWordRange: focusWordRange)
    }
    .buttonStyle(.bordered)
    .accessibilityLabel(
      source == .attempt ? "Play your take at the target" : "Play reference at the target")
    .disabled(model.isRecording || model.isAnalyzing)
  }
}
