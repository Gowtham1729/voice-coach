import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

@MainActor
protocol SessionChatResponding {
  func respond(to request: SessionChatRequest) async throws -> SessionChatReply
}

enum SessionChatError: LocalizedError {
  case unavailable
  case contextTooLarge
  case unsupportedLanguage
  case refused
  case emptyResponse

  var errorDescription: String? {
    switch self {
    case .unavailable: "On-device chat is unavailable. Check Apple Intelligence in System Settings."
    case .contextTooLarge:
      "That request is too long for the local model. Ask about one shorter line."
    case .unsupportedLanguage:
      "The local model does not support that language. Try another one."
    case .refused: "The local model could not answer that. Try asking about the line another way."
    case .emptyResponse: "The local model returned no answer. Try again."
    }
  }
}

/// Adapts Apple's on-device model to a language reply. A fresh session keeps one
/// recording's question from inheriting another recording's transcript.
struct LocalSessionChatResponder: SessionChatResponding {
  func respond(to request: SessionChatRequest) async throws -> SessionChatReply {
    guard CoachingWordingGenerator.status == .available else { throw SessionChatError.unavailable }
    #if canImport(FoundationModels)
      let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: 768)
      let session = LanguageModelSession(instructions: request.instructions)
      do {
        let response = try await session.respond(to: request.prompt, options: options)
        try Task.checkCancellation()
        let reply = SessionChatReply(answer: response.content)
        guard !reply.answer.isEmpty else { throw SessionChatError.emptyResponse }
        return reply
      } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
        throw SessionChatError.contextTooLarge
      } catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale {
        throw SessionChatError.unsupportedLanguage
      } catch LanguageModelSession.GenerationError.guardrailViolation {
        throw SessionChatError.refused
      }
    #else
      throw SessionChatError.unavailable
    #endif
  }

}
