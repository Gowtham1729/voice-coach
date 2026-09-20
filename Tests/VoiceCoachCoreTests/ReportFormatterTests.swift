import Foundation
import Testing
import VoiceCoachCore

@Suite("Report formatter contracts")
struct ReportFormatterTests {
  @Test("Compact export keeps the six objective sections")
  func compactShape() throws {
    let report = ReportFormatter.makeCompactReport(session: CoreTestFixtures.session())
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(report.utf8)) as? [String: Any]
    )

    #expect(
      Set(object.keys) == [
        "recording", "recording_quality", "pitch", "loudness", "pauses", "voice_quality",
      ])
    #expect(report.contains("cpp_db") == false)
  }

  @Test("Expanded export includes transcript and word data without subjective coaching")
  func expandedShape() throws {
    let report = ReportFormatter.makeReport(session: CoreTestFixtures.session())
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(report.utf8)) as? [String: Any]
    )

    #expect(object["transcription"] != nil)
    #expect((object["words"] as? [[String: Any]])?.count == 3)
    let lowercased = report.lowercased()
    #expect(lowercased.contains("baseline") == false)
    #expect(lowercased.contains("throat") == false)
    #expect(lowercased.contains("cpp_db") == false)
  }
}
