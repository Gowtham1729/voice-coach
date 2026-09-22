import Foundation
import OSLog
import VoiceCoachCore

#if canImport(FoundationModels)
  import FoundationModels
#endif

private let insightCopyLog = Logger(subsystem: "com.gowtham.voicecoach", category: "InsightCopy")

/// On-device Apple Foundation Models Insight wording. Fail-closed to frozen `HeroPacket` copy.
struct InsightCopyGenerator: InsightCopyGenerating {
  enum Status: Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable

    var availability: InsightCopyAvailability {
      switch self {
      case .available: .available
      case .deviceNotEligible: .deviceNotEligible
      case .appleIntelligenceNotEnabled: .appleIntelligenceNotEnabled
      case .modelNotReady: .modelNotReady
      case .unavailable: .unavailable
      }
    }

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
      switch SystemLanguageModel.default.availability {
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

  var availability: InsightCopyAvailability { Self.status.availability }

  static func prewarmIfAvailable() {
    guard InsightWordingPreference.isEnabled, status == .available else { return }
    #if canImport(FoundationModels)
      LanguageModelSession(instructions: InsightCopyPrompt.instructions).prewarm()
    #endif
  }

  func rewrite(_ packet: HeroPacket) async -> InsightCopyRewrite? {
    guard packet.isValid else {
      insightCopyLog.notice("skip: invalid HeroPacket")
      return nil
    }
    guard Self.status == .available else {
      insightCopyLog.notice(
        "skip: Foundation Models \(Self.status.settingsLabel, privacy: .public)")
      return nil
    }

    #if canImport(FoundationModels)
      return await withTimeout(seconds: 4) {
        await generateGuidedWording(packet: packet)
      }
    #else
      return nil
    #endif
  }

  #if canImport(FoundationModels)
    private func generateGuidedWording(packet: HeroPacket) async -> InsightCopyRewrite? {
      do {
        let session = LanguageModelSession(instructions: InsightCopyPrompt.instructions)
        let options = GenerationOptions(samplingMode: .greedy, temperature: 0.0)
        let response = try await session.respond(
          to: InsightCopyPrompt.userMessage(for: packet),
          generating: CoachingWording.self,
          options: options
        )
        let rewrite = InsightCopyRewrite(
          observation: response.content.observation,
          action: response.content.action
        )
        insightCopyLog.info(
          "rewrite \(packet.claimID.rawValue, privacy: .public)/\(packet.actionID.rawValue, privacy: .public)"
        )
        return rewrite
      } catch {
        insightCopyLog.error("generable failed: \(error.localizedDescription, privacy: .public)")
        return nil
      }
    }

    private func withTimeout<T: Sendable>(
      seconds: Double,
      operation: @escaping @Sendable () async -> T?
    ) async -> T? {
      await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
          try? await Task.sleep(for: .seconds(seconds))
          return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
      }
    }
  #endif
}

#if canImport(FoundationModels)
  @Generable
  struct CoachingWording {
    @Guide(description: "Rewritten observation, same meaning as the approved sentence")
    var observation: String
    @Guide(description: "Rewritten next-take action, same meaning as the approved sentence")
    var action: String
  }
#endif
