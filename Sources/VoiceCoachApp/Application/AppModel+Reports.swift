import AppKit
import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  func copyReport() { copyToPasteboard(report, message: "JSON copied") }

  func copyAICoachPrompt() {
    guard let session = selectedSession, !report.isEmpty else { return }
    let coachPrompt = """
      You are a speech coach. Use only the JSON for “\(session.name)”. Name the strongest patterns, the two highest-impact improvements, and three exercises for the next take. Treat HNR as an acoustic signal, not a diagnosis. CPP is not provided—do not invent it. Do not invent observations the data does not support.

      VOICE COACH JSON
      \(report)
      """
    copyToPasteboard(coachPrompt, message: "Copied")
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
      You are a speech coach for Mimic practice. The user matched a reference (“\(context.session.name)”). Practice style is in the JSON.

      Use only the JSON. Goal: closer timing, pitch shape, emphasis, and pauses—not identical pitch or loudness.

      - Treat hnr_db as an acoustic signal, not medical. Do not invent CPP.
      - If alignment.reliable is false or alignment.words is missing, skip word-level deltas and say so.
      - Do not invent words, pauses, or metrics.

      Return:
      1) Strongest matches (0–3)
      2) Two highest-impact gaps
      3) Three exercises for the next take

      MIMIC COMPARE JSON
      \(json)
      """
    copyToPasteboard(coachPrompt, message: "Copied")
  }

  func copyMimicCompareJSON() {
    guard let json = mimicCompareReportJSON() else { return }
    copyToPasteboard(json, message: "JSON copied")
  }

  private func copyToPasteboard(_ value: String, message: String) {
    guard !value.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    toastMessage = message
  }
}
