import Testing
import VoiceCoachCore
@testable import VoiceCoachApp

@Suite("Practice clip editor")
struct PracticeClipEditorTests {
  @Test("Switching phrases preserves each edit and selected batch membership")
  func retainedEdits() throws {
    var editor = PracticeClipEditor(clips: clips, duration: 10)
    #expect(editor.selectedIDs == [0] && editor.activeSelection.start == clips[0].start)
    editor.setBoundary(0.3, isStart: true)
    editor.select(2)
    #expect(editor.activeSelection.start == clips[1].start)
    editor.setBoundary(5, isStart: false)
    editor.select(0)
    #expect(editor.activeSelection.start == 0.3)
    #expect(editor.creationSelections.map(\.end) == [clips[0].end, 5])
    editor.setSelected(0, selected: false)
    #expect(editor.activeID == 2 && editor.creationSelections.count == 1)
    editor.select(0)
    #expect(editor.activeSelection.start == 0.3)
    editor.resetActiveClip()
    #expect(editor.activeSelection.start == clips[0].start && !editor.activeIsAdjusted)
    editor.setBoundary(clips[0].start + 0.1, isStart: true)
    editor.setBoundary(editor.activeSelection.start - 0.1, isStart: true)
    #expect(editor.activeSelection.start == clips[0].start && !editor.activeIsAdjusted)
  }

  @Test("Custom clipping clears batch membership and returning to a phrase restores its edit")
  func customClip() {
    var editor = PracticeClipEditor(clips: clips, duration: 10)
    editor.setBoundary(0.4, isStart: true)
    editor.select(2)
    editor.chooseCustomClip()
    #expect(editor.selectedIDs.isEmpty && editor.activeID == nil)
    #expect(editor.creationSelections.count == 1 && editor.creationSelections[0].phraseID == nil)
    editor.setBoundary(8, isStart: false)
    editor.select(0)
    #expect(editor.creationSelections.count == 1 && editor.activeSelection.start == 0.4)
    #expect(editor.creationSelections[0].phraseID == 0)
  }

  @Test("Trimming stays in the audio and preserves a one-second minimum")
  func boundaryLimits() {
    var editor = PracticeClipEditor(clips: [], duration: 10)
    editor.setBoundary(-10, isStart: true)
    editor.setBoundary(100, isStart: false)
    #expect(editor.activeSelection.start == 0 && editor.activeSelection.end == 10)
    editor.setBoundary(100, isStart: true)
    #expect(editor.activeSelection.start == 9)
    editor.setBoundary(-1, isStart: false)
    #expect(editor.activeSelection.end == 10)
    editor.setBoundary(.nan, isStart: true)
    #expect(editor.activeSelection.start == 9)
  }

  private var clips: [SuggestedPracticeClip] {
    PracticeClipSuggestions.clips(transcription: TranscriptionResult(
      text: "First phrase. Second phrase.", words: [
        TranscriptWord(word: "First", start: 0.2, end: 0.8),
        TranscriptWord(word: "phrase.", start: 0.9, end: 1.6),
        TranscriptWord(word: "Second", start: 3, end: 3.6),
        TranscriptWord(word: "phrase.", start: 3.7, end: 4.4),
      ]), duration: 10)
  }
}
