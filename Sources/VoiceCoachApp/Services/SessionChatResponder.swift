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
  case unhelpfulResponse

  var errorDescription: String? {
    switch self {
    case .unavailable: "On-device chat is unavailable. Check Apple Intelligence in System Settings."
    case .contextTooLarge:
      "The complete transcript and conversation exceed the local model’s context limit. Clear the chat to retry without earlier messages, or use a shorter recording."
    case .unsupportedLanguage:
      "The local model does not support that language. Try another one."
    case .refused: "The local model could not answer that. Try rephrasing your question."
    case .emptyResponse: "The local model returned no answer. Try again."
    case .unhelpfulResponse:
      "The local model didn't answer the language question. Try asking about a specific word."
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
        if case .synonym = request.task {
          let response = try await session.respond(
            to: request.prompt, generating: SessionChatSynonymDraft.self, options: options)
          try Task.checkCancellation()
          guard
            let reply = SessionChatSynonymAnswer.make(
              response.content.entries.map {
                .init(word: $0.word, synonym: $0.synonym, difference: $0.difference)
              }, transcript: request.transcript)
          else { throw SessionChatError.unhelpfulResponse }
          return reply
        }
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

#if canImport(FoundationModels)
  @Generable
  private struct SessionChatSynonymDraft {
    @Guide(
      description:
        "Three candidate synonym pairs using different clear words from the transcript. Skip names and uncertain phrases.",
      .count(3)
    )
    var entries: [SessionChatSynonymEntry]
  }

  @Generable
  private struct SessionChatSynonymEntry {
    @Guide(
      description:
        "Copy one clearly understood content word exactly from the transcript."
    )
    var word: String
    @Guide(
      description:
        "An alternative vocabulary word with similar meaning. Examples: important has the synonym significant; début has the synonym commencement. The alternative must differ from the word field."
    )
    var synonym: String
    @Guide(
      description:
        "A short explanation of the difference in meaning or usage, in the user's requested language. Explain language only, not recording performance."
    )
    var difference: String
  }
#endif
