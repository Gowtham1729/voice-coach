import Foundation
import VoiceCoachCore

struct MimicReferenceDraft {
  let id: UUID
  let url: URL
  let sourceName: String
  let duration: Double
  let peaks: [Float]
  let source: TakeSource
}

enum MimicPhase: Equatable {
  case ready
  case playingReference
  case countIn(Int)
  case recording
  case analyzing
}

enum MimicWorkspaceMode: String, CaseIterable, Identifiable {
  case practice
  case compare
  case analysis

  var id: Self { self }

  var title: String {
    switch self {
    case .practice: "Practice"
    case .compare: "Compare"
    case .analysis: "Analysis"
    }
  }

  var inspectorTitle: String {
    switch self {
    case .practice: "Practice"
    case .compare: "Comparison"
    case .analysis: "Analysis"
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
    case .attempt: "You"
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
