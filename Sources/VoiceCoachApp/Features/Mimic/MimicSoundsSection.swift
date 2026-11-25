import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

/// User-facing words for Sound comparison (PRD UX-3, UX-5, UX-6). Never a score, never "wrong".
enum SoundComparisonCopy {
  static let section = "Sounds"
  static let listen = "Listen"
  static let stop = "Stop"
  static let caption = "Sounded different from your reference. Listen plays the reference, then yours."
  static let running = "Comparing sounds…"
  static let noFlags = "No clear sound differences found."
  static let failed = "Couldn’t compare sounds right now. Open this take again to retry."

  static func flagSentence(_ word: String) -> String {
    "\(word) sounded different from your reference."
  }

  static func listenHelp(_ word: String) -> String {
    "Plays \(word) from your reference, then from your take, then from your reference again."
  }

  /// Nil when another part of Review already says it (a non-English take gets the English-only
  /// note in the coaching card) or there is nothing to compare against.
  static func notComparable(_ reason: SoundComparisonSkipReason) -> String? {
    let why: String
    switch reason {
    case .noReference, .notEnglish: return nil
    case .referenceAudioMissing: why = "the reference audio is missing or can’t be opened"
    case .takeAudioMissing: why = "this take’s audio is missing or can’t be opened"
    case .missingTranscript: why = "there’s no transcript"
    case .wordsDidNotLineUp: why = "the words didn’t line up"
    case .noisy: why = "the audio was noisy"
    case .clipping: why = "the audio was too loud"
    }
    return "Couldn’t compare sounds in this take: \(why)."
  }
}

/// The Sounds section of the Compare inspector: words the transcript heard differently (FR-1)
/// and, with a Sound comparison engine, words that sounded different (UX-2, UX-6). One row per
/// word, in transcript order, each with Listen.
struct MimicSoundsSection: View {
  @EnvironmentObject private var model: AppModel
  let session: CoachingSession
  let reference: PracticeSession
  let take: PracticeSession

  var body: some View {
    let comparison = MimicComparison.compare(reference: reference, attempt: take)
    let status = model.soundComparisonStatus(sessionID: session.id, takeID: take.id)
    let flags: [SoundFlagRow] =
      if case .ready(let result) = status {
        model.soundFlagRows(for: take, in: session, result: result)
      } else { [] }
    let flaggedWords = Set(flags.map(\.referenceWordIndex))
    let heard = comparison.heardDifferently
      .filter { !flaggedWords.contains($0.referenceIndex) }
      .map(SoundFlagRows.heardRow)
    let rows = (flags + heard).sorted { $0.referenceWordIndex < $1.referenceWordIndex }
    let line = statusLine(status, hasRows: !rows.isEmpty)

    if !rows.isEmpty || line != nil {
      // Same shape as Metrics just above: eyebrow, then rows on one content panel.
      VStack(alignment: .leading, spacing: 8) {
        SectionEyebrow(text: SoundComparisonCopy.section)
        if !rows.isEmpty {
          Text(SoundComparisonCopy.caption)
            .font(.caption)
            .foregroundStyle(Studio.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        VStack(spacing: 0) {
          ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            if index > 0 { Divider().padding(.leading, 12) }
            flagRow(row)
          }
          if let line {
            if !rows.isEmpty { Divider().padding(.leading, 12) }
            statusView(line, running: status == .running || status == .pending)
          }
        }
        .desktopPanel()
      }
    }
  }

  private func flagRow(_ row: SoundFlagRow) -> some View {
    let isListening = model.soundListenWordIndex == row.referenceWordIndex
    return HStack(alignment: .center, spacing: 10) {
      VStack(alignment: .leading, spacing: 1) {
        Text(row.word)
          .font(.callout.weight(.medium))
        if let heard = row.heard {
          Text("We heard: \(Text(heard).italic())")
            .font(.caption)
            .foregroundStyle(Studio.secondary)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        SoundComparisonCopy.flagSentence(row.word)
          + (row.heard.map { " We heard: \($0)." } ?? ""))
      .frame(maxWidth: .infinity, alignment: .leading)
      if row.takeRange != nil {
        // Same control as the retry card's replay buttons: a play icon, so it reads as audio.
        Button {
          model.listenToSoundFlag(row)
        } label: {
          Label(
            isListening ? SoundComparisonCopy.stop : SoundComparisonCopy.listen,
            systemImage: isListening ? "stop.fill" : "play.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .disabled(model.isRecording || model.isAnalyzing)
        .help(SoundComparisonCopy.listenHelp(row.word))
        .accessibilityLabel(
          isListening ? "Stop listening" : "Listen to \(row.word): reference, your take, reference")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private func statusView(_ line: String, running: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      if running {
        ProgressView().controlSize(.mini)
      }
      Text(line)
        .font(.caption)
        .foregroundStyle(Studio.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
  }

  /// One line for every state except a shown flag list (UX-6). Nothing without an engine.
  private func statusLine(_ status: SoundComparisonStatus, hasRows: Bool) -> String? {
    switch status {
    case .noEngine: nil
    case .notComparable(let reason): SoundComparisonCopy.notComparable(reason)
    case .running, .pending: SoundComparisonCopy.running
    case .failed: SoundComparisonCopy.failed
    case .ready: hasRows ? nil : SoundComparisonCopy.noFlags
    }
  }
}
