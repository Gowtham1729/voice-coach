import Foundation
import OSLog
import VoiceCoachCore

#if canImport(FoundationModels)
  import FoundationModels
#endif

private let coachingLog = Logger(subsystem: "com.gowtham.voicecoach", category: "CoachingWording")

/// Rephrases two already selected exercises on device. Facts and ranking stay in CoachingPlanner.
struct CoachingWordingGenerator {
  enum Status: Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable

    var settingsLabel: String {
      switch self {
      case .available: "Ready"
      case .deviceNotEligible: "Not supported on this Mac"
      case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in System Settings"
      case .modelNotReady: "Apple Intelligence is still downloading"
      case .unavailable: "Unavailable"
      }
    }
  }

  static var status: Status {
    #if canImport(FoundationModels)
      let model = SystemLanguageModel.default
      guard model.supportsLocale(Locale.current) else { return .unavailable }
      return switch model.availability {
      case .available: .available
      case .unavailable(.deviceNotEligible): .deviceNotEligible
      case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceNotEnabled
      case .unavailable(.modelNotReady): .modelNotReady
      case .unavailable: .unavailable
      }
    #else
      .unavailable
    #endif
  }

  private static let instructions = """
    Rewrite two approved voice-practice exercises in plain, encouraging language.
    Preserve each exercise's scope, target word, direction, and relationship to a reference when present.
    Keep the measured skill named in the approved action: pitch, pace or timing, or emphasis.
    When an exercise covers the phrase, say "phrase" and use the named word only as a checkpoint.
    Do not add facts, numerical targets, diagnoses, emotions, or another exercise.
    One short sentence per exercise. No headings, quotes around the whole sentence, or markdown.
    """

  static func prewarmIfAvailable() {
    guard InsightWordingPreference.isEnabled, status == .available else { return }
    #if canImport(FoundationModels)
      LanguageModelSession(instructions: instructions).prewarm()
    #endif
  }

  func rewriteActions(for plan: CoachingPlan) async -> [String]? {
    guard plan.signals.count == 2, Self.status == .available else { return nil }
    #if canImport(FoundationModels)
      let prompt = plan.signals.enumerated().map { index, signal in
        """
        Exercise \(index + 1): \(signal.title)
        Measured observation: \(signal.observation)
        Approved action: \(signal.action)
        """
      }.joined(separator: "\n\n")
      do {
        let response = try await LanguageModelSession(instructions: Self.instructions).respond(
          to: prompt,
          generating: CoachingActionWording.self,
          // Xcode 26.6 CI still labels this initializer `sampling:`.
          options: GenerationOptions(sampling: .greedy, temperature: 0)
        )
        let raw = [response.content.firstAction, response.content.secondAction]
        let resolved = zip(raw, plan.signals).map { action, signal in
          CoachingActionRules.accepted(action, for: signal)
        }
        let acceptedCount = resolved.compactMap { $0 }.count
        coachingLog.info("accepted \(acceptedCount) of 2 local wording suggestions")
        guard acceptedCount > 0 else { return nil }
        return zip(resolved, plan.signals).map { $0 ?? $1.action }
      } catch {
        coachingLog.error("local wording failed: \(error.localizedDescription, privacy: .public)")
        return nil
      }
    #else
      return nil
    #endif
  }
}

#if canImport(FoundationModels)
  @Generable
  struct CoachingActionWording {
    @Guide(description: "A one-sentence exercise that preserves exercise 1's scope, checkpoint, and direction")
    var firstAction: String
    @Guide(description: "A one-sentence exercise that preserves exercise 2's scope, checkpoint, and direction")
    var secondAction: String
  }
#endif
