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
}
