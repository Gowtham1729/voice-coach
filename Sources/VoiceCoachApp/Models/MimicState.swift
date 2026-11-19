import Foundation
import VoiceCoachCore

struct MimicReferenceDraft {
  let id: UUID
  let url: URL
  let sourceName: String
  let duration: Double
  let peaks: [Float]
  let source: TakeSource
  var transcription: TranscriptionResult? = nil
  var transcriptionLocaleIdentifier: String? = nil
}

enum MimicPhase: Equatable {
  case ready
  case playingReference
  case countIn(Int)
  case recording
  case analyzing
}

/// Two views a person chooses between: Practice and Review. `.analysis` is Review's
/// "Take details" sub-view (your take on its own), not a third tab.
enum MimicWorkspaceMode: String, CaseIterable, Identifiable {
  case practice
  case compare
  case analysis

  var id: Self { self }

  /// The segments of the Practice / Review switch.
  static let switchCases: [MimicWorkspaceMode] = [.practice, .compare]

  var title: String {
    switch self {
    case .practice: "Practice"
    case .compare: "Review"
    case .analysis: "Take details"
    }
  }

  /// Which switch segment shows as selected.
  var switchCase: MimicWorkspaceMode { self == .analysis ? .compare : self }

  var inspectorTitle: String {
    switch self {
    case .practice: "Practice"
    case .compare: "Review"
    case .analysis: "Take details"
    }
  }
}

enum MimicPlaybackSource: CaseIterable, Identifiable {
  case reference
  case attempt

  var id: Self { self }

  var title: String {
    switch self {
    case .reference: "Reference"
    case .attempt: "Your take"
    }
  }

  var help: String {
    switch self {
    case .reference: "Play reference"
    case .attempt: "Play your take"
    }
  }
}

struct ReplaceOnlyPrompt: Equatable {
  enum Kind: Equatable {
    case record
    case importClip
  }

  let sessionID: UUID
  let kind: Kind
}
