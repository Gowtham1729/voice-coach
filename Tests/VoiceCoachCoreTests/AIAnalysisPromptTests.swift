import Foundation
import Testing
import VoiceCoachCore

@Suite("External AI analysis prompt")
struct AIAnalysisPromptTests {
  @Test("Take prompt includes the full expanded report as data")
  func takePrompt() throws {
    let json = ReportFormatter.makeReport(session: CoreTestFixtures.session())
    let prompt = AIAnalysisPrompt.forTake(reportJSON: json)
    let copiedJSON = try embeddedJSON(in: prompt)

    #expect(copiedJSON == json)
    #expect(prompt.contains("exactly two prioritized practice signals"))
    #expect(prompt.contains("without a reference or earlier attempt"))
    #expect(!prompt.contains("three exercises"))
  }

  @Test("Mimic prompt includes alignment and avoids false start-delay or progress claims")
  func mimicPrompt() throws {
    let json = ReportFormatter.makeMimicCompareReport(
      reference: CoreTestFixtures.session(), attempt: CoreTestFixtures.session(),
      practiceStyle: "Listen & Repeat")
    let prompt = AIAnalysisPrompt.forMimic(reportJSON: json)
    let copiedJSON = try embeddedJSON(in: prompt)

    #expect(copiedJSON == json)
    #expect(prompt.contains("alignment.reliable"))
    #expect(prompt.contains("constant start offset"))
    #expect(prompt.contains("No earlier attempt is included"))
    #expect(prompt.contains("exactly two prioritized practice signals"))
  }

  private func embeddedJSON(in prompt: String) throws -> String {
    let opening = "<voice_coach_json>\n"
    let closing = "\n</voice_coach_json>"
    let start = try #require(prompt.range(of: opening)?.upperBound)
    let end = try #require(prompt.range(of: closing)?.lowerBound)
    let json = String(prompt[start..<end])
    let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
    #expect(object is [String: Any])
    return json
  }
}
