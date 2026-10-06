import Foundation

/// Copy and button rules the take screen, Home, and Words pane read.
/// Kept here so the contract can be tested without rendering SwiftUI.
package enum TakeScreenCopy {
  package static let homeSubtitle = "Record a phrase, or practice with a reference."
  package static let missingTranscriptLine = "No transcript for this take."
  package static let retranscribe = "Re-transcribe"
  package static let record = "Record"
  package static let export = "Export"
  package static let tryAgain = "Try again"
  /// Existing analysis status. Not a new sentence.
  package static let analyzing = "Analyzing…"

  /// A zero count is never shown, including while transcription is still running.
  package static func wordCountLabel(wordCount: Int, transcriptionRunning: Bool) -> String? {
    if transcriptionRunning, wordCount <= 0 { return nil }
    guard wordCount > 0 else { return nil }
    return "\(wordCount) words"
  }
}

package struct TakeActionChrome: Equatable {
  package var filledTitles: [String]
  package var exportSitsWithDelete: Bool

  package func isFilled(_ title: String) -> Bool {
    filledTitles.contains(title)
  }

  /// Saved plain take: Record is the only filled control. Export is not.
  package static func plainTake() -> TakeActionChrome {
    TakeActionChrome(filledTitles: [TakeScreenCopy.record], exportSitsWithDelete: true)
  }

  /// Compare while the reference and the take are both showing.
  package static func compare(bothTargetsShowing: Bool) -> TakeActionChrome {
    TakeActionChrome(
      filledTitles: bothTargetsShowing ? [TakeScreenCopy.tryAgain] : [],
      exportSitsWithDelete: true
    )
  }
}

package struct WordsPaneChrome: Equatable {
  package var lines: [String]
  package var actions: [String]
  package var showsComposer: Bool
  package var showsAskField: Bool
  package var showsExploreWords: Bool
  package var showsZero: Bool
  package var keepsConversation: Bool

  package static func make(hasTranscript: Bool, transcriptionRunning: Bool) -> WordsPaneChrome {
    if transcriptionRunning {
      return WordsPaneChrome(
        lines: [TakeScreenCopy.analyzing],
        actions: [],
        showsComposer: false,
        showsAskField: false,
        showsExploreWords: false,
        showsZero: false,
        keepsConversation: hasTranscript
      )
    }
    if !hasTranscript {
      // Transcript already owns Re-transcribe. Words is the line only.
      return WordsPaneChrome(
        lines: [TakeScreenCopy.missingTranscriptLine],
        actions: [],
        showsComposer: false,
        showsAskField: false,
        showsExploreWords: false,
        showsZero: false,
        keepsConversation: false
      )
    }
    return WordsPaneChrome(
      lines: [],
      actions: [],
      showsComposer: true,
      showsAskField: true,
      showsExploreWords: true,
      showsZero: false,
      keepsConversation: true
    )
  }
}
