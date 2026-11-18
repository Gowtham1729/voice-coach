import Foundation
import Testing
import VoiceCoachCore
import VoiceCoachSession

@Suite("Practice list")
struct PracticeCatalogTests {
  private func take(_ name: String) -> PracticeSession {
    SessionTestFixtures.take(audioURL: URL(fileURLWithPath: "/tmp/\(name).wav"))
  }

  @Test("Filters show each practice once and keep archived ones apart")
  func filters() {
    var plain = SessionTestFixtures.session(take: take("plain"))
    plain.takes.append(take("plain-2"))
    let reference = SessionTestFixtures.session(take: take("ref"), mode: .mimic)
    let archived = SessionTestFixtures.session(take: take("old"), archived: true)
    var empty = SessionTestFixtures.session(take: take("empty"))
    empty.takes = []
    let all = [plain, reference, archived, empty]

    #expect(Set(PracticeCatalog.practices(from: all, filter: .all).map(\.id)) == [plain.id, reference.id])
    #expect(PracticeCatalog.practices(from: all, filter: .withReference).map(\.id) == [reference.id])
    #expect(PracticeCatalog.practices(from: all, filter: .archived).map(\.id) == [archived.id])
  }

  @Test("Archived plain recordings leave the take catalog too")
  func archivedPlainRecording() {
    let archived = SessionTestFixtures.session(take: take("archived"), archived: true)
    #expect(RecordingCatalog.recordings(from: [archived]).isEmpty)
  }

  @Test("Search matches the title and transcripts")
  func search() {
    var session = SessionTestFixtures.session(take: take("named"))
    session.name = "Conference opener"
    #expect(PracticeCatalog.practices(from: [session], filter: .all, query: "opener").count == 1)
    #expect(PracticeCatalog.practices(from: [session], filter: .all, query: "nothing").isEmpty)
  }

  @Test("Rows describe takes and the reference badge")
  func detail() {
    var plain = SessionTestFixtures.session(take: take("one"))
    #expect(PracticeCatalog.detail(of: plain) == "1 take")
    plain.takes.append(take("two"))
    #expect(PracticeCatalog.detail(of: plain) == "2 takes")
    let reference = SessionTestFixtures.session(take: take("ref"), mode: .mimic)
    #expect(PracticeCatalog.detail(of: reference) == "1 take · With reference")
  }

  @Test("Groups by last activity")
  func grouping() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(PracticeListGroup.group(for: now, now: now, calendar: calendar) == .today)
    #expect(
      PracticeListGroup.group(for: now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar)
        == .thisWeek)
    #expect(
      PracticeListGroup.group(for: now.addingTimeInterval(-30 * 86_400), now: now, calendar: calendar)
        == .earlier)
  }
}
