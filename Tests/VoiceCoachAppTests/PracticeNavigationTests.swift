import Foundation
import Testing
import VoiceCoachSession

@testable import VoiceCoachApp

@Suite("Practice list navigation", .serialized)
@MainActor
struct PracticeNavigationTests {
  @Test("Cancelling New practice returns to where the sheet opened")
  func cancelReturnsToPreviousList() throws {
    let fixture = try QuickPracticeFixture()
    defer { fixture.cleanUp() }
    fixture.model.showList(.withReference)
    #expect(fixture.model.destination == .mimics)

    fixture.model.destination = .mimicStart
    fixture.model.returnFromCreateSheet()

    #expect(fixture.model.destination == .mimics)
    #expect(fixture.model.listFilter == .withReference)
  }

  @Test("A practice that no longer exists falls back to the start panel")
  func cancelFallsBackWhenPracticeIsGone() throws {
    let fixture = try QuickPracticeFixture()
    defer { fixture.cleanUp() }
    fixture.model.destination = .practice(UUID())
    fixture.model.destination = .mimicStart
    fixture.model.returnFromCreateSheet()

    #expect(fixture.model.destination == .home)
  }

  @Test("List filters select the matching list destination")
  func showList() throws {
    let fixture = try QuickPracticeFixture()
    defer { fixture.cleanUp() }
    fixture.model.showList(.archived)
    #expect(fixture.model.listFilter == .archived)
    #expect(fixture.model.destination == .library)
    fixture.model.showList(.all)
    #expect(fixture.model.listFilter == .all)
    #expect(fixture.model.selectedSessionID == nil)
  }
}
