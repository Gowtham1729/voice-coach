import AppKit
import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  func copyReport() { copyToPasteboard(report, message: "Word-level voice data copied") }

  func copyAICoachPrompt() {
    guard let session = selectedSession, !report.isEmpty else { return }
    let coachPrompt = """
      You are an expert speech coach. Assess the objective acoustic measurements for the recording below (“\(session.name)”). Explain the strongest delivery patterns, identify the two highest-impact improvements, and give three specific exercises for the next take. Treat HNR as an acoustic proxy, not a medical measurement. CPP is not provided—do not invent it. Do not invent observations that are not supported by the data.

      VOICE COACH JSON
      \(report)
      """
    copyToPasteboard(coachPrompt, message: "AI coach prompt copied")
  }

  private var mimicCompareContext:
    (session: CoachingSession, reference: PracticeSession, take: PracticeSession, style: String)?
  {
    guard let session = selectedSession,
      let reference = session.mimicReference?.take,
      let take = selectedTake
    else { return nil }
    let style = (session.mimicAttemptStyles?[take.id] ?? session.mimicStyle ?? .listenAndRepeat)
      .title
    return (session, reference, take, style)
  }

  func mimicCompareReportJSON() -> String? {
    guard let context = mimicCompareContext else { return nil }
    return ReportFormatter.makeMimicCompareReport(
      reference: context.reference,
      attempt: context.take,
      practiceStyle: context.style
    )
  }

  var mimicCompareAlignmentReliable: Bool {
    guard let context = mimicCompareContext else { return false }
    return MimicComparison.compare(reference: context.reference, attempt: context.take)
      .correspondenceReliable
  }

  func copyMimicCoachPrompt() {
    guard let context = mimicCompareContext else { return }
    let json = ReportFormatter.makeMimicCompareReport(
      reference: context.reference,
      attempt: context.take,
      practiceStyle: context.style
    )
    let coachPrompt = """
      You are an expert speech coach helping with Mimic practice.
      The user tried to match a reference clip (“\(context.session.name)”).
      Practice style for this attempt is included in the JSON.

      Use ONLY the JSON below. Goal: sound closer to the reference on timing, pitch contour shape, emphasis, and pause placement—not identical absolute pitch or loudness level (reference may be another speaker).

      Rules:
      - Treat hnr_db as an acoustic proxy only; not medical. CPP is not provided—do not invent it.
      - If alignment.reliable is false or alignment.words is absent: ignore word-level deltas; use recording-level metrics, contours, and transcripts only. Say when word comparison is unavailable.
      - Do not invent words, pauses, or metrics. Matched words are an LCS subset; skipped/added words may be missing from alignment.
      - Prefer concrete, listen-verifiable cues (e.g. longer pause before X, flatter contour on Y).

      Return:
      1) Strongest matches (0–3, skip if none)
      2) Two highest-impact gaps vs the reference
      3) Three specific exercises for the next take (style-aware)

      MIMIC COMPARE JSON
      \(json)
      """
    copyToPasteboard(coachPrompt, message: "Mimic coach prompt copied")
  }

  func copyMimicCompareJSON() {
    guard let json = mimicCompareReportJSON() else { return }
    copyToPasteboard(json, message: "Compare JSON copied")
  }

  private func copyToPasteboard(_ value: String, message: String) {
    guard !value.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    toastMessage = message
  }
}
