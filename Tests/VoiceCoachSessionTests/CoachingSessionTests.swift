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

  @Test("LibraryRecording sidebarTitle and sidebarSubtitle format correctly")
  func libraryRecordingSidebarProperties() {
    let take = SessionTestFixtures.take(audioURL: URL(fileURLWithPath: "/tmp/take.wav"))
    let session = SessionTestFixtures.session(take: take)
    let recording = LibraryRecording.make(session: session, take: take)!

    #expect(recording.iconSymbol == "mic.fill")
    #expect(recording.sidebarTitle == "Practice")
    #expect(recording.sidebarSubtitle == "Recorded")

    // Multi-take retry stack
    var retrySession = session
    let secondTake = SessionTestFixtures.take(audioURL: URL(fileURLWithPath: "/tmp/take2.wav"))
    retrySession.takes.append(secondTake)
    let retryRec1 = LibraryRecording.make(session: retrySession, take: take)!
    let retryRec2 = LibraryRecording.make(session: retrySession, take: secondTake)!

    #expect(retryRec1.sidebarTitle == "Practice")
    #expect(retryRec1.sidebarSubtitle == "Take 1 of 2")
    #expect(retryRec2.sidebarTitle == "Practice")
    #expect(retryRec2.sidebarSubtitle == "Take 2 of 2")

    // Prompted retry stack
    var promptSession = session
    promptSession.prompt = "Tell me about yourself and your background in engineering"
    let promptRec = LibraryRecording.make(session: promptSession, take: take)!
    #expect(promptRec.sidebarTitle == "Tell me about yourself and your background in…")
    #expect(promptRec.sidebarSubtitle == "Take 1 of 1")

    // Mimic attempt
    let mimicRef = MimicReference(sourceName: "Reference Speech", take: take, sourceStart: 0, sourceEnd: 2)
    var mimicSession = session
    mimicSession.mode = .mimic
    mimicSession.mimicReference = mimicRef
    let mimicRec = LibraryRecording.make(session: mimicSession, take: take)!
    #expect(mimicRec.iconSymbol == "waveform.path")
    #expect(mimicRec.sidebarTitle == "Reference Speech")
    #expect(mimicRec.sidebarSubtitle == "Mimic attempt")
  }
}
