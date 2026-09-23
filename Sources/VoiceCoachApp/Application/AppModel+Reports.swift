import AppKit
import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  func copyReport() { copyToPasteboard(report, message: "JSON copied") }

  func copySelectedAIAnalysisPrompt() {
    if isMimicWorkspace && mimicWorkspaceMode == .compare {
      copyMimicAIAnalysisPrompt()
    } else {
      copyAIAnalysisPrompt()
    }
  }

  func copyAIAnalysisPrompt() {
    let json = report
    guard !json.isEmpty else { return }
    copyToPasteboard(
      AIAnalysisPrompt.forTake(reportJSON: json), message: "AI prompt + JSON copied")
  }

  private var mimicCompareContext:
    (reference: PracticeSession, take: PracticeSession, style: String)?
  {
    guard let session = selectedSession,
      let reference = session.mimicReference?.take,
      let take = selectedTake
    else { return nil }
    let style = (session.mimicAttemptStyles?[take.id] ?? session.mimicStyle ?? .listenAndRepeat)
      .title
    return (reference, take, style)
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

  func copyMimicAIAnalysisPrompt() {
    guard let json = mimicCompareReportJSON() else { return }
    copyToPasteboard(
      AIAnalysisPrompt.forMimic(reportJSON: json), message: "AI prompt + JSON copied")
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
