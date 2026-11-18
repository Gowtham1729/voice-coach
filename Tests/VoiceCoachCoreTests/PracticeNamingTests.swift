import Testing
import VoiceCoachCore

@Suite("Practice titles")
struct PracticeNamingTests {
  @Test("File names drop bitrate noise and underscores")
  func cleansFileNames() {
    #expect(PracticeNaming.cleaned(fileName: "Interview clip (128k)") == "Interview clip")
    #expect(PracticeNaming.cleaned(fileName: "talk_final [320kbps]") == "talk final")
    #expect(PracticeNaming.cleaned(fileName: "Lesson 3 (128 KB/s) part") == "Lesson 3 part")
    #expect(PracticeNaming.cleaned(fileName: "Plain name") == "Plain name")
  }

  @Test("Cleaning never returns an empty title")
  func keepsOriginalWhenEmpty() {
    #expect(PracticeNaming.cleaned(fileName: "(128k)") == "(128k)")
  }

  @Test("Transcript titles use the opening words")
  func transcriptTitles() {
    #expect(PracticeNaming.fromTranscript("Hello there") == "Hello there")
    #expect(
      PracticeNaming.fromTranscript("one two three four five six seven eight nine")
        == "one two three four five six seven eight…")
    #expect(PracticeNaming.fromTranscript("   ") == nil)
  }
}
