import Foundation
import VoiceCoachCore
import VoiceCoachSession

extension AppModel {
  func sessionChatContext(session: CoachingSession, take: PracticeSession?) -> SessionChatContext? {
    SessionChatContext(session: session, take: take)
  }

  func conversation(for context: SessionChatContext) -> SessionChatConversation {
    if let existing = sessionChats[context.scope], existing.context == context {
      if let focus = pendingChatFocus.removeValue(forKey: context.scope) { existing.focus = focus }
      return existing
    }
    sessionChats[context.scope]?.cancel()
    let conversation = SessionChatConversation(context: context, responder: sessionChatResponder)
    if let focus = pendingChatFocus.removeValue(forKey: context.scope) { conversation.focus = focus }
    sessionChats[context.scope] = conversation
    return conversation
  }

  func focusSessionChat(_ passage: String, session: CoachingSession, take: PracticeSession) {
    guard ExperimentalFeaturesPreference.isEnabled,
      let context = sessionChatContext(session: session, take: take)
    else { return }
    if let chat = sessionChats[context.scope], chat.context == context {
      chat.focus = passage
    } else {
      pendingChatFocus[context.scope] = passage
    }
  }

  func revealSessionChat() {
    guard ExperimentalFeaturesPreference.isEnabled else { return }
    askInspectorNonce += 1
  }

  func removeSessionChats(sessionID: UUID, takeID: UUID? = nil) {
    let scopes = sessionChats.keys.filter {
      $0.sessionID == sessionID && (takeID == nil || $0.takeID == takeID)
    }
    for scope in scopes {
      sessionChats.removeValue(forKey: scope)?.clear()
    }
  }

  func clearExperimentalChats() {
    sessionChats.values.forEach { $0.clear() }
    sessionChats.removeAll()
  }
}
