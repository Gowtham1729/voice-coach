import Testing
import VoiceCoachCore

@Suite("Practice titles")
struct PracticeTitleTests {
  @Test("File names drop bitrate noise and underscores")
  func cleansFileNames() {
    #expect(PracticeTitle.cleaned(fileName: "Interview clip (128k)") == "Interview clip")
    #expect(PracticeTitle.cleaned(fileName: "talk_final [320kbps]") == "talk final")
    #expect(PracticeTitle.cleaned(fileName: "Lesson 3 (128 KB/s) part") == "Lesson 3 part")
    #expect(PracticeTitle.cleaned(fileName: "Plain name") == "Plain name")
  }

  @Test("Cleaning never returns an empty title")
  func keepsOriginalWhenEmpty() {
    #expect(PracticeTitle.cleaned(fileName: "(128k)") == "(128k)")
  }

  @Test("Transcript titles use the opening words")
  func transcriptTitles() {
    #expect(PracticeTitle.fromTranscript("Hello there") == "Hello there")
    #expect(
      PracticeTitle.fromTranscript("one two three four five six seven eight nine")
        == "one two three four five six seven eight…")
    #expect(PracticeTitle.fromTranscript("   ") == nil)
  }
}
