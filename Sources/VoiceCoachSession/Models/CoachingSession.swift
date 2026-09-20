import Foundation
import VoiceCoachCore

package enum PracticeMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case general
  case prompt
  case freeSpeaking
  case mimic

  // Keep legacy cases decodable for existing libraries, but new capture is Record or Mimic.
  package static var allCases: [PracticeMode] { [.general, .mimic] }

  package var id: Self { self }

  package var title: String {
    switch self {
    case .general: "General practice"
    case .prompt: "Read a prompt"
    case .freeSpeaking: "Free speaking"
    case .mimic: "Mimic a reference"
    }
  }

  package var detail: String {
    switch self {
    case .general: "Speak freely on any topic. Build consistency and confidence."
    case .prompt: "Read a short prompt aloud. Focus on clarity and delivery."
    case .freeSpeaking: "Speak on a topic of your choice. Develop structure and fluency."
    case .mimic: "Listen, imitate a short clip, compare, and retry."
    }
  }

  package var icon: String {
    switch self {
    case .general: "mic.fill"
    case .prompt: "doc.text.fill"
    case .freeSpeaking: "chart.bar.fill"
    case .mimic: "waveform.path"
    }
  }
}

package enum MimicStyle: String, Codable, CaseIterable, Identifiable, Sendable {
  case listenAndRepeat
  case speakAlong

  package var id: Self { self }
  package var title: String {
    switch self {
    case .listenAndRepeat: "Listen & Repeat"
    case .speakAlong: "Speak Along"
    }
  }
}

package struct MimicReference: Codable, Equatable, Sendable {
  package var sourceName: String
  package var take: PracticeSession
  package var sourceStart: Double
  package var sourceEnd: Double

  package init(sourceName: String, take: PracticeSession, sourceStart: Double, sourceEnd: Double) {
    self.sourceName = sourceName
    self.take = take
    self.sourceStart = sourceStart
    self.sourceEnd = sourceEnd
  }
}

package struct CoachingSession: Codable, Identifiable, Equatable, Sendable {
  package let id: UUID
  package var name: String
  package let createdAt: Date
  package var updatedAt: Date
  package var mode: PracticeMode
  package var prompt: String
  package var keepsRecordings: Bool
  package var takes: [PracticeSession]
  package var mimicReference: MimicReference?
  package var mimicStyle: MimicStyle?
  package var mimicAttemptStyles: [UUID: MimicStyle]?
  package var archived: Bool

  package init(
    id: UUID = UUID(),
    name: String,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    mode: PracticeMode,
    prompt: String,
    keepsRecordings: Bool,
    takes: [PracticeSession] = [],
    mimicReference: MimicReference? = nil,
    mimicStyle: MimicStyle? = nil,
    mimicAttemptStyles: [UUID: MimicStyle]? = nil,
    archived: Bool = false
  ) {
    self.id = id
    self.name = name
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.mode = mode
    self.prompt = prompt
    self.keepsRecordings = keepsRecordings
    self.takes = takes
    self.mimicReference = mimicReference
    self.mimicStyle = mimicStyle
    self.mimicAttemptStyles = mimicAttemptStyles
    self.archived = archived
  }

  package var latestTake: PracticeSession? { takes.last }
  package var takeCount: Int { takes.count }
  package var isMimic: Bool { mode == .mimic }
  package var trimmedPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
  /// Visible grouping for repeating general work. Mimic is a separate workspace.
  package var isRetryStack: Bool { !isMimic && (!trimmedPrompt.isEmpty || takes.count >= 2) }
  package var isStandaloneRecording: Bool { !isMimic && trimmedPrompt.isEmpty && takes.count == 1 }
  package var isEmptyLegacy: Bool { !isMimic && takes.isEmpty }

  package func takeNumber(for takeID: UUID) -> Int? {
    guard let index = takes.firstIndex(where: { $0.id == takeID }) else { return nil }
    return index + 1
  }

  package func userRecordedDuration() -> Double {
    takes.reduce(0) { sum, take in
      take.takeSource == .recorded ? sum + take.result.metrics.duration : sum
    }
  }

  var allPracticeTakes: [PracticeSession] {
    var items = takes
    if let reference = mimicReference?.take {
      items.append(reference)
    }
    return items
  }

  enum CodingKeys: String, CodingKey {
    case id, name, createdAt, updatedAt, mode, prompt, keepsRecordings, takes
    case mimicReference, mimicStyle, mimicAttemptStyles, archived
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    mode = try container.decode(PracticeMode.self, forKey: .mode)
    prompt = try container.decode(String.self, forKey: .prompt)
    keepsRecordings = try container.decode(Bool.self, forKey: .keepsRecordings)
    takes = try container.decodeIfPresent([PracticeSession].self, forKey: .takes) ?? []
    mimicReference = try container.decodeIfPresent(MimicReference.self, forKey: .mimicReference)
    mimicStyle = try container.decodeIfPresent(MimicStyle.self, forKey: .mimicStyle)
    mimicAttemptStyles = try container.decodeIfPresent(
      [UUID: MimicStyle].self, forKey: .mimicAttemptStyles)
    archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(updatedAt, forKey: .updatedAt)
    try container.encode(mode, forKey: .mode)
    try container.encode(prompt, forKey: .prompt)
    try container.encode(keepsRecordings, forKey: .keepsRecordings)
    try container.encode(takes, forKey: .takes)
    try container.encodeIfPresent(mimicReference, forKey: .mimicReference)
    try container.encodeIfPresent(mimicStyle, forKey: .mimicStyle)
    try container.encodeIfPresent(mimicAttemptStyles, forKey: .mimicAttemptStyles)
    if archived { try container.encode(true, forKey: .archived) }
  }
}

package enum RecordingTitle {
  package static func make(date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "d MMM, h:mm a"
    return "Recording · \(formatter.string(from: date))"
  }
}
