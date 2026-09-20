import VoiceCoachSession

enum LibraryFilter: String, CaseIterable, Identifiable {
  case all
  case recorded
  case imported
  case mimic

  var id: Self { self }

  var title: String {
    switch self {
    case .all: "All"
    case .recorded: "Recorded"
    case .imported: "Imported"
    case .mimic: "Mimic"
    }
  }

  func matches(_ recording: LibraryRecording) -> Bool {
    switch self {
    case .all: true
    case .recorded: !recording.isImported && !recording.isMimicAttempt
    case .imported: recording.isImported && !recording.isMimicAttempt
    case .mimic: recording.isMimicAttempt
    }
  }
}
