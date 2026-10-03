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

/// Adapts Apple's on-device model to a guided reply. A fresh session keeps one
/// recording's question from inheriting another recording's transcript.
struct LocalSessionChatResponder: SessionChatResponding {
  func respond(to request: SessionChatRequest) async throws -> SessionChatReply {
    guard CoachingWordingGenerator.status == .available else { throw SessionChatError.unavailable }
    #if canImport(FoundationModels)
      let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: 200)
      let session = LanguageModelSession(instructions: request.instructions)
      do {
        let response = try await session.respond(
          to: request.prompt,
          generating: SessionChatDraft.self,
          options: options
        )
        try Task.checkCancellation()
        return try finalized(response.content.answer, practiceLine: response.content.practiceLine)
      } catch let error as SessionChatError {
        throw error
      } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
        throw SessionChatError.contextTooLarge
      } catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale {
        throw SessionChatError.unsupportedLanguage
      } catch LanguageModelSession.GenerationError.guardrailViolation {
        throw SessionChatError.refused
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        let response = try await LanguageModelSession(instructions: request.instructions).respond(
          to: request.prompt,
          options: options
        )
        try Task.checkCancellation()
        return try finalized(response.content, practiceLine: nil)
      }
    #else
      throw SessionChatError.unavailable
    #endif
  }

  private func finalized(_ answer: String, practiceLine: String?) throws -> SessionChatReply {
    let reply = SessionChatReply(answer: answer, practiceLine: practiceLine)
    if !reply.answer.isEmpty || reply.practiceLine != nil { return reply }
    if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return .voiceBoundary
    }
    throw SessionChatError.emptyResponse
  }
}

#if canImport(FoundationModels)
  @Generable
  struct SessionChatDraft {
    @Guide(description: "The answer itself, in plain sentences. No preamble.")
    var answer: String
    @Guide(description: "A single sentence to say aloud, or empty.")
    var practiceLine: String
  }
#endif
