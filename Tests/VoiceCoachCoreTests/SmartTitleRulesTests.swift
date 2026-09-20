import Testing
import VoiceCoachCore

@Suite("Smart title rules")
struct SmartTitleRulesTests {
  @Test("Transcript gates reject underspecified input")
  func transcriptGates() {
    #expect(SmartTitleRules.transcriptPassesGates("Too short") == false)
    #expect(
      SmartTitleRules.transcriptPassesGates(
        "A clear project update with enough useful spoken context"))
  }

  @Test("Sanitization accepts concise titles and rejects unsafe coaching claims")
  func sanitization() {
    #expect(SmartTitleRules.sanitize("  “Quarterly Launch Update”  ") == "Quarterly Launch Update")
    #expect(SmartTitleRules.sanitize("Medical throat diagnosis") == nil)
    #expect(SmartTitleRules.sanitize(String(repeating: "x", count: 57)) == nil)
  }
}
