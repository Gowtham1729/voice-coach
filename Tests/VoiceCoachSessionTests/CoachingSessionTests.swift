import Foundation
import Testing
import VoiceCoachCore
import VoiceCoachSession

@Suite("Session domain")
struct CoachingSessionTests {
  @Test("Session classifications preserve standalone, retry, and Mimic semantics")
  func classifications() {
    let first = SessionTestFixtures.take(audioURL: URL(fileURLWithPath: "/tmp/first.wav"))
    var session = SessionTestFixtures.session(take: first)

    #expect(session.isStandaloneRecording)
    #expect(session.isRetryStack == false)

    session.takes.append(
      SessionTestFixtures.take(audioURL: URL(fileURLWithPath: "/tmp/second.wav")))
    #expect(session.isRetryStack)
    #expect(session.takeNumber(for: session.takes[1].id) == 2)
  }

  @Test("Recording catalog excludes archived Mimic attempts by default")
  func archivedCatalogFiltering() {
    let generalTake = SessionTestFixtures.take(audioURL: URL(fileURLWithPath: "/tmp/general.wav"))
    let mimicTake = SessionTestFixtures.take(audioURL: URL(fileURLWithPath: "/tmp/mimic.wav"))
    let general = SessionTestFixtures.session(take: generalTake)
    let archivedMimic = SessionTestFixtures.session(take: mimicTake, mode: .mimic, archived: true)

    #expect(
      RecordingCatalog.recordings(from: [general, archivedMimic]).map(\.id) == [generalTake.id])
    #expect(
      RecordingCatalog.recordings(from: [general, archivedMimic], includeArchived: true).count == 2)
  }

  @Test("Legacy decoding defaults archived to false")
  func legacyArchivedDefault() throws {
    let take = SessionTestFixtures.take(audioURL: URL(fileURLWithPath: "/tmp/legacy.wav"))
    let session = SessionTestFixtures.session(take: take)
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any]
    )
    object.removeValue(forKey: "archived")
    let data = try JSONSerialization.data(withJSONObject: object)

    #expect(try JSONDecoder().decode(CoachingSession.self, from: data).archived == false)
  }
}
