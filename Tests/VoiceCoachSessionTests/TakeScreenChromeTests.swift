import Foundation
import Testing
import VoiceCoachSession

@Suite("Take screen chrome")
struct TakeScreenChromeTests {
  @Test("Home subtitle uses the exact practice line")
  func homeSubtitle() {
    #expect(TakeScreenCopy.homeSubtitle == "Record a phrase, or practice with a reference.")
  }

  @Test("A plain take fills Record and leaves Export unfilled beside Delete")
  func plainTakePrimary() {
    let chrome = TakeActionChrome.plainTake()
    #expect(chrome.filledTitles == ["Record"])
    #expect(chrome.isFilled(TakeScreenCopy.record))
    #expect(!chrome.isFilled(TakeScreenCopy.export))
    #expect(!chrome.filledTitles.contains("Export"))
    #expect(!chrome.filledTitles.contains("Record again"))
    #expect(chrome.exportSitsWithDelete)
    #expect(TakeScreenCopy.record == "Record")
  }

  @Test("Compare fills Try again only when both targets are showing")
  func comparePrimary() {
    let showing = TakeActionChrome.compare(bothTargetsShowing: true)
    #expect(showing.filledTitles == ["Try again"])
    #expect(showing.filledTitles.count == 1)
    #expect(showing.isFilled(TakeScreenCopy.tryAgain))
    #expect(!showing.isFilled(TakeScreenCopy.export))
    #expect(!showing.isFilled(TakeScreenCopy.record))
    #expect(!showing.filledTitles.contains("Record again"))

    let hidden = TakeActionChrome.compare(bothTargetsShowing: false)
    #expect(hidden.filledTitles.isEmpty)
    #expect(!hidden.isFilled(TakeScreenCopy.tryAgain))
  }

  @Test("Words with no transcript shows one line and Re-transcribe, never zero or an ask field")
  func missingTranscript() {
    let chrome = WordsPaneChrome.make(hasTranscript: false, transcriptionRunning: false)
    #expect(chrome.lines == ["No transcript for this take."])
    #expect(chrome.actions == ["Re-transcribe"])
    #expect(chrome.actions.count == 1)
    #expect(!chrome.showsComposer)
    #expect(!chrome.showsAskField)
    #expect(!chrome.showsExploreWords)
    #expect(!chrome.showsZero)
    #expect(!chrome.keepsConversation)
    expectNoZeroOrAsk(chrome)
    #expect(!chrome.actions.contains("Record again"))
    #expect(!chrome.lines.contains("Record again"))
    #expect(!chrome.lines.contains("Explore the words"))
  }

  @Test("In-progress transcription keeps Analyzing… and does not show zero or an ask field")
  func transcriptionInProgress() {
    for hasTranscript in [false, true] {
      let chrome = WordsPaneChrome.make(
        hasTranscript: hasTranscript, transcriptionRunning: true)
      #expect(chrome.lines == ["Analyzing…"])
      #expect(chrome.actions.isEmpty)
      #expect(!chrome.showsComposer)
      #expect(!chrome.showsAskField)
      #expect(!chrome.showsZero)
      #expect(!chrome.showsExploreWords)
      #expect(chrome.keepsConversation == hasTranscript)
      expectNoZeroOrAsk(chrome)
      #expect(!chrome.lines.contains(TakeScreenCopy.missingTranscriptLine))
    }
    #expect(TakeScreenCopy.wordCountLabel(wordCount: 0, transcriptionRunning: true) == nil)
    #expect(TakeScreenCopy.wordCountLabel(wordCount: 4, transcriptionRunning: true) == "4 words")
  }

  @Test("A failed transcript never renders a zero word count")
  func failedTranscriptWordCount() {
    #expect(TakeScreenCopy.wordCountLabel(wordCount: 0, transcriptionRunning: false) == nil)
    #expect(TakeScreenCopy.wordCountLabel(wordCount: -1, transcriptionRunning: false) == nil)
    #expect(TakeScreenCopy.wordCountLabel(wordCount: 3, transcriptionRunning: false) == "3 words")
  }

  private func expectNoZeroOrAsk(_ chrome: WordsPaneChrome) {
    let rendered = chrome.lines + chrome.actions
    #expect(!rendered.contains("0"))
    #expect(!rendered.contains { $0.split(separator: " ").contains("0") })
    #expect(!rendered.contains { $0.localizedCaseInsensitiveContains("ask") })
  }
}
