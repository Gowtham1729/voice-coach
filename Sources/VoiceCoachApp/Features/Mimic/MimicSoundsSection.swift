import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

/// User-facing words for Sound comparison (PRD UX-3, UX-5, UX-6). Never a score, never "wrong".
enum SoundComparisonCopy {
  static let section = "Sounds"
  static let listen = "Listen"
  static let stop = "Stop"
  static let running = "Comparing sounds…"
  static let noFlags = "No clear sound differences from your reference in this take."
  static let failed = "Couldn’t compare sounds in this take. Open it again later to retry."
  static let noReference =
    "To see words that sounded different, practice with a reference, or choose Use as reference… on a take you like."

  static func flagSentence(_ word: String) -> String {
    "\(word) sounded different from your reference."
  }

  static func listenHelp(_ word: String) -> String {
    "Plays \(word) from your reference, then from your take, then from your reference again."
  }

  static func notComparable(_ reason: SoundComparisonSkipReason) -> String {
    let why =
      switch reason {
      case .noReference: "there’s no reference"
      case .referenceAudioMissing: "the reference audio is missing or can’t be opened"
      case .takeAudioMissing: "this take’s audio is missing or can’t be opened"
      case .notEnglish: "it isn’t English"
      case .missingTranscript: "there’s no transcript"
      case .wordsDidNotLineUp: "the words didn’t line up"
      case .noisy: "the audio was noisy"
      case .clipping: "the audio was too loud"
      }
    return "Couldn’t compare sounds in this take: \(why)."
  }
}

/// The Sounds section of the Compare inspector: words the transcript heard differently (FR-1)
/// and, with a Sound comparison engine, words that sounded different (UX-2, UX-6).
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
    let heard = comparison.heardDifferently.filter { !flaggedWords.contains($0.referenceIndex) }
    let line = statusLine(status, hasFlags: !flags.isEmpty)

    if !flags.isEmpty || !heard.isEmpty || line != nil {
      // Same shape as Metrics just above: eyebrow, then rows on one content panel.
      VStack(alignment: .leading, spacing: 8) {
        SectionEyebrow(text: SoundComparisonCopy.section)
        if !flags.isEmpty || !heard.isEmpty {
          VStack(spacing: 0) {
            ForEach(Array(flags.enumerated()), id: \.element.id) { index, row in
              if index > 0 { Divider() }
              flagRow(row)
            }
            ForEach(Array(heard.enumerated()), id: \.element.referenceIndex) { index, difference in
              if index > 0 || !flags.isEmpty { Divider() }
              heardRow(difference)
            }
          }
          .desktopPanel()
        }
        if let line {
          statusView(line, running: status == .running || status == .pending)
        }
      }
    }
  }

  private func flagRow(_ row: SoundFlagRow) -> some View {
    let isListening = model.soundListenWordIndex == row.referenceWordIndex
    return HStack(alignment: .firstTextBaseline, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text("\(Text(row.word).italic()) sounded different from your reference.")
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
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

  private func heardRow(_ difference: MimicHeardDifference) -> some View {
    let reference = SoundFlagRows.displayWord(difference.reference.word)
    let heard = SoundFlagRows.displayWord(difference.attempt.word)
    return Text("Reference: \(Text(reference).italic()) · We heard: \(Text(heard).italic())")
      .font(.callout)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .accessibilityLabel("Reference: \(reference). We heard: \(heard).")
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
    .accessibilityElement(children: .combine)
  }

  /// One line for every state except a shown flag list (UX-6). Nothing without an engine.
  private func statusLine(_ status: SoundComparisonStatus, hasFlags: Bool) -> String? {
    switch status {
    case .noEngine: nil
    case .notComparable(let reason): SoundComparisonCopy.notComparable(reason)
    case .running, .pending: SoundComparisonCopy.running
    case .failed: SoundComparisonCopy.failed
    case .ready: hasFlags ? nil : SoundComparisonCopy.noFlags
    }
  }
}
