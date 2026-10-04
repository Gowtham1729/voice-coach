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

  var passages: [SessionChatPassage] {
    SessionChatPassages.make(origin: .attempt, text: transcript)
      + SessionChatPassages.make(origin: .reference, text: referenceTranscript)
  }

  static let missingTranscript = "No transcript."

  /// The line a question uses when the person has not picked one.
  var fallbackQuote: String {
    if let line = passages.first(where: { $0.origin == (isMimic ? .reference : .attempt) })?.text
      ?? passages.first?.text
    {
      return line
    }
    return Self.missingTranscript
  }

}
