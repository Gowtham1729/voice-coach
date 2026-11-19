import Foundation

/// Which practices the list shows. Archived practices only appear under `.archived`.
package enum PracticeListFilter: String, CaseIterable, Identifiable, Sendable {
  case all
  case withReference
  case archived

  package var id: Self { self }

  package var title: String {
    switch self {
    case .all: "All practices"
    case .withReference: "With reference"
    case .archived: "Archived"
    }
  }

  package var symbol: String {
    switch self {
    case .all: "tray.full"
    case .withReference: "waveform.path"
    case .archived: "archivebox"
    }
  }

  package func includes(_ session: CoachingSession) -> Bool {
    if session.isEmptyLegacy { return false }
    switch self {
    case .all: return !session.archived
    case .withReference: return session.isMimic && !session.archived
    case .archived: return session.archived
    }
  }
}

/// Date buckets for the practice list, by last activity.
package enum PracticeListGroup: Int, CaseIterable, Identifiable, Sendable {
  case today
  case thisWeek
  case earlier

  package var id: Self { self }

  package var title: String {
    switch self {
    case .today: "Today"
    case .thisWeek: "Previous 7 days"
    case .earlier: "Earlier"
    }
  }

  package static func group(
    for date: Date, now: Date = Date(), calendar: Calendar = .current
  ) -> PracticeListGroup {
    if calendar.isDate(date, inSameDayAs: now) { return .today }
    let startOfToday = calendar.startOfDay(for: now)
    if let weekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday), date >= weekAgo {
      return .thisWeek
    }
    return .earlier
  }
}

/// One practice per row: the list never shows loose takes.
package enum PracticeCatalog {
  package static func practices(
    from sessions: [CoachingSession], filter: PracticeListFilter, query: String = ""
  ) -> [CoachingSession] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return
      sessions
      .filter { filter.includes($0) && matches($0, query: trimmed) }
      .sorted { $0.updatedAt > $1.updatedAt }
  }

  package static func grouped(
    _ sessions: [CoachingSession], now: Date = Date(), calendar: Calendar = .current
  ) -> [(group: PracticeListGroup, sessions: [CoachingSession])] {
    let buckets = Dictionary(grouping: sessions) {
      PracticeListGroup.group(for: $0.updatedAt, now: now, calendar: calendar)
    }
    return PracticeListGroup.allCases.compactMap { group in
      guard let items = buckets[group], !items.isEmpty else { return nil }
      return (group, items)
    }
  }

  /// The one name a practice goes by everywhere.
  package static func title(of session: CoachingSession) -> String {
    if let source = session.mimicReference?.sourceName, !source.isEmpty { return source }
    return session.name
  }

  /// "3 takes · With reference" style detail for a row.
  package static func detail(of session: CoachingSession) -> String {
    let takes = session.takeCount == 1 ? "1 take" : "\(session.takeCount) takes"
    return session.isMimic ? "\(takes) · With reference" : takes
  }

  package static func matches(_ session: CoachingSession, query: String) -> Bool {
    guard !query.isEmpty else { return true }
    if title(of: session).localizedCaseInsensitiveContains(query) { return true }
    if session.name.localizedCaseInsensitiveContains(query) { return true }
    if session.prompt.localizedCaseInsensitiveContains(query) { return true }
    if session.mimicReference?.take.transcription?.text.localizedCaseInsensitiveContains(query)
      == true
    {
      return true
    }
    return session.takes.contains {
      $0.transcription?.text.localizedCaseInsensitiveContains(query) == true
    }
  }
}
