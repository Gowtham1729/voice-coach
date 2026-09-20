import Foundation
import VoiceCoachCore

/// User-facing library row. Mimic references are never included.
package struct LibraryRecording: Identifiable, Equatable, Sendable {
  package let sessionID: UUID
  package let take: PracticeSession
  package let groupName: String
  package let prompt: String
  package let isMimicAttempt: Bool
  package let mimicSourceName: String?
  package let takeNumber: Int
  package let takeCount: Int
  package let isRetryStack: Bool
  package let archived: Bool

  package var id: UUID { take.id }
  package var isImported: Bool { take.takeSource != .recorded }

  package var iconSymbol: String {
    isMimicAttempt ? "waveform.path" : take.takeSource.icon
  }

  package var sidebarTitle: String {
    if isMimicAttempt {
      return mimicSourceName.flatMap { $0.isEmpty ? nil : $0 } ?? groupName
    }
    if isRetryStack {
      return stackLabel
    }
    return groupName
  }

  package var sidebarSubtitle: String {
    if isMimicAttempt { return "Mimic attempt" }
    return take.takeSource.title
  }

  package var displayTitle: String {
    if isMimicAttempt {
      let source = mimicSourceName.flatMap { $0.isEmpty ? nil : $0 } ?? groupName
      return "\(source) · Take \(takeNumber) · \(Self.timeText(take.createdAt))"
    }
    if isRetryStack {
      return "\(stackLabel) · Take \(takeNumber) · \(Self.timeText(take.createdAt))"
    }
    return groupName
  }

  package var subtitle: String {
    if isMimicAttempt { return "Mimic attempt" }
    if isRetryStack { return prompt.isEmpty ? "Take \(takeNumber) of \(takeCount)" : prompt }
    return take.takeSource.title
  }

  package var accessibilityLabel: String {
    if isMimicAttempt {
      let source = mimicSourceName ?? groupName
      return "Take \(takeNumber) of \(takeCount), Mimic, \(source)"
    }
    if isRetryStack {
      return "Take \(takeNumber) of \(takeCount), \(stackLabel)"
    }
    return "\(groupName), \(take.takeSource.title)"
  }

  package var stackLabel: String {
    guard !prompt.isEmpty else { return groupName }
    let excerpt = prompt.split(separator: " ").prefix(8).joined(separator: " ")
    guard prompt.count > excerpt.count else { return excerpt }
    return "\(excerpt)…"
  }

  private static func timeText(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }

  package static func make(session: CoachingSession, take: PracticeSession) -> LibraryRecording? {
    guard let number = session.takeNumber(for: take.id) else { return nil }
    return LibraryRecording(
      sessionID: session.id,
      take: take,
      groupName: session.name,
      prompt: session.trimmedPrompt,
      isMimicAttempt: session.isMimic,
      mimicSourceName: session.mimicReference?.sourceName,
      takeNumber: number,
      takeCount: session.takeCount,
      isRetryStack: session.isRetryStack,
      archived: session.archived
    )
  }

  package func matches(query: String) -> Bool {
    guard !query.isEmpty else { return true }
    if displayTitle.localizedCaseInsensitiveContains(query) { return true }
    if groupName.localizedCaseInsensitiveContains(query) { return true }
    if prompt.localizedCaseInsensitiveContains(query) { return true }
    if mimicSourceName?.localizedCaseInsensitiveContains(query) == true { return true }
    if take.takeSource.title.localizedCaseInsensitiveContains(query) { return true }
    return take.transcription?.text.localizedCaseInsensitiveContains(query) == true
  }
}

package enum RecordingCatalog {
  package static func recordings(from sessions: [CoachingSession], includeArchived: Bool = false)
    -> [LibraryRecording]
  {
    sessions.flatMap { session in
      if session.isMimic, session.archived, !includeArchived { return [] as [LibraryRecording] }
      return session.takes.compactMap { LibraryRecording.make(session: session, take: $0) }
    }
    .sorted { $0.take.createdAt > $1.take.createdAt }
  }

  package static func recording(takeID: UUID, in sessions: [CoachingSession]) -> LibraryRecording? {
    for session in sessions {
      if let take = session.takes.first(where: { $0.id == takeID }) {
        return LibraryRecording.make(session: session, take: take)
      }
    }
    return nil
  }
}
