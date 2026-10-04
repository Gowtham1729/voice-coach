import Foundation
import VoiceCoachCore
import VoiceCoachSession

/// A recording chat never receives the library or another take's conversation.
struct SessionChatContext: Equatable, Sendable {
  struct Scope: Hashable, Sendable {
    let sessionID: UUID
    let takeID: UUID
  }

  let scope: Scope
  let title: String
  let isMimic: Bool
  let transcript: String?
  let referenceTranscript: String?

  init?(session: CoachingSession, take: PracticeSession?) {
    guard let takeID = take?.id ?? session.mimicReference?.take.id else { return nil }
    scope = Scope(sessionID: session.id, takeID: takeID)
    isMimic = session.isMimic
    let number = take.flatMap { session.takeNumber(for: $0.id) }
    title =
      session.isMimic
      ? "\(session.name) · \(number.map { "Take \($0)" } ?? "Reference")"
      : session.name
    transcript = take?.transcription?.text
    referenceTranscript = session.mimicReference?.take.transcription?.text
  }

  var hasTranscript: Bool {
    [transcript, referenceTranscript].contains {
      !($0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
  }

  var sources: [SessionChatTranscript] {
    [SessionChatTranscript.Origin.reference, .attempt].compactMap { origin in
      let text = origin == .reference ? referenceTranscript : transcript
      guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
      }
      return SessionChatTranscript(origin: origin, text: text)
    }
  }

  static let missingTranscript = "No transcript."

  var defaultTranscript: SessionChatTranscript? {
    sources.first { $0.origin == (isMimic ? .reference : .attempt) } ?? sources.first
  }
}
