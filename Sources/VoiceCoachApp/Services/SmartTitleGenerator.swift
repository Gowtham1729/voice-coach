import Foundation
import FoundationModels
import OSLog
import VoiceCoachCore

private let smartTitleLog = Logger(subsystem: "com.gowtham.voicecoach", category: "SmartTitle")

/// On-device Apple Foundation Models title suggestions. Soft-fails to `nil`.
enum SmartTitleGenerator {
  private static let instructions = """
    You name short voice-practice recordings for a local coaching studio.
    Return a concise, specific title (about 3 to 6 words) that reflects what was said.
    Neutral and descriptive. No medical or diagnostic language. No quotes. No trailing punctuation.
    """

  enum Status: Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable

    var settingsLabel: String {
      switch self {
      case .available: "Ready"
      case .deviceNotEligible: "This Mac can’t run Apple Intelligence"
      case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in System Settings"
      case .modelNotReady: "Apple Intelligence model still downloading or preparing"
      case .unavailable: "Unavailable"
      }
    }

    var settingsFooter: String {
      switch self {
      case .available:
        "On-device Apple Foundation Models. Titles stay on this Mac."
      case .deviceNotEligible:
        "Smart titles need an Apple Intelligence–compatible Mac."
      case .appleIntelligenceNotEnabled:
        "Enable Apple Intelligence & Siri in System Settings, then return here."
      case .modelNotReady:
        "Keep this Mac online until Apple Intelligence finishes downloading. Date titles are used until then."
      case .unavailable:
        "Smart titles can’t run right now. Date or filename titles are used instead."
      }
    }
  }

  static var status: Status {
    switch SystemLanguageModel.default.availability {
    case .available: .available
    case .unavailable(.deviceNotEligible): .deviceNotEligible
    case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceNotEnabled
    case .unavailable(.modelNotReady): .modelNotReady
    case .unavailable: .unavailable
    }
  }

  static func suggestTitle(from transcript: String) async -> String? {
    guard AutoTitlePreference.isEnabled else {
      smartTitleLog.debug("skip: preference off")
      return nil
    }
    guard SmartTitleRules.transcriptPassesGates(transcript) else {
      smartTitleLog.debug("skip: transcript gates")
      return nil
    }

    let modelStatus = status
    guard modelStatus == .available else {
      smartTitleLog.notice("skip: Foundation Models \(modelStatus.settingsLabel, privacy: .public)")
      return nil
    }

    let clipped = SmartTitleRules.clipTranscript(transcript)
    if let title = await generateGuidedTitle(clipped: clipped) {
      return title
    }
    return await generatePlainTitle(clipped: clipped)
  }

  static func prewarmIfAvailable() {
    guard AutoTitlePreference.isEnabled, status == .available else { return }
    LanguageModelSession(instructions: instructions).prewarm()
  }

  private static func generateGuidedTitle(clipped: String) async -> String? {
    do {
      let session = LanguageModelSession(instructions: instructions)
      let response = try await session.respond(
        to: "Name this practice take from the transcript:\n\(clipped)",
        generating: PracticeTitle.self
      )
      return acceptedTitle(response.content.title, source: "generable")
    } catch {
      smartTitleLog.error("generable failed: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  private static func generatePlainTitle(clipped: String) async -> String? {
    do {
      let session = LanguageModelSession(instructions: instructions)
      let response = try await session.respond(
        to: "Name this practice take in 3 to 6 words. Reply with the title only.\n\(clipped)"
      )
      return acceptedTitle(response.content, source: "plain")
    } catch {
      smartTitleLog.error("plain failed: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  private static func acceptedTitle(_ raw: String, source: String) -> String? {
    guard let title = SmartTitleRules.sanitize(raw) else {
      smartTitleLog.notice(
        "skip: \(source, privacy: .public) sanitize rejected '\(raw, privacy: .public)'")
      return nil
    }
    smartTitleLog.info("title (\(source, privacy: .public)): \(title, privacy: .public)")
    return title
  }
}

@Generable
struct PracticeTitle {
  @Guide(description: "Short practice title, about 3 to 6 words, no quotes")
  var title: String
}
