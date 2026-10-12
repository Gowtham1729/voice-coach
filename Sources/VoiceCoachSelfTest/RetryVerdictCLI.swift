import Foundation
import VoiceCoachCore
import VoiceCoachSession

private struct CopiedAnalysis: Decodable {
  let schemaVersion: Int
  let result: AnalysisResult
  let transcription: TranscriptionResult?
  let words: [WordAnalysis]
}

func printRetryVerdicts(at input: URL) throws {
  let manager = FileManager.default
  let sessions: [CoachingSession]
  if manager.fileExists(atPath: input.appendingPathComponent("session-library.json").path) {
    sessions = try SessionStore(rootURL: input).load().filter(\.isMimic)
  } else {
    // A copied Sessions/<UUID> folder has no thin index. The reference is the
    // analysis file without a matching take WAV. Style metadata is unavailable,
    // so all practice WAVs in this folder are treated as one style.
    let files = try manager.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
    let analyses = files.filter { $0.lastPathComponent.hasSuffix(".analysis.json") }
    let decoded: [(URL, UUID, CopiedAnalysis)] = try analyses.map { url in
      let name = url.lastPathComponent
      let idText = String(name.dropFirst("take-".count).dropLast(".analysis.json".count))
      guard let id = UUID(uuidString: idText) else { throw CocoaError(.coderReadCorrupt) }
      let document = try JSONDecoder().decode(CopiedAnalysis.self, from: Data(contentsOf: url))
      guard document.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
      return (url, id, document)
    }
    func matchingWAV(_ id: UUID) -> URL? {
      files.first { $0.lastPathComponent.hasPrefix("take-\(id.uuidString)")
        && $0.pathExtension.lowercased() == "wav" }
    }
    guard let referenceEntry = decoded.first(where: { matchingWAV($0.1) == nil }),
      let referenceWAV = files.first(where: { $0.lastPathComponent == "reference.wav" })
    else { throw CocoaError(.fileReadNoSuchFile) }
    func take(_ item: (URL, UUID, CopiedAnalysis), audio: URL) -> PracticeSession {
      PracticeSession(id: item.1, audioURL: audio, result: item.2.result,
        transcription: item.2.transcription, words: item.2.words)
    }
    let reference = take(referenceEntry, audio: referenceWAV)
    let attempts = decoded.filter { $0.1 != referenceEntry.1 }.compactMap { entry in
      matchingWAV(entry.1).map { take(entry, audio: $0) }
    }.sorted { $0.audioURL.lastPathComponent < $1.audioURL.lastPathComponent }
    let session = CoachingSession(
      id: UUID(), name: input.lastPathComponent, mode: .mimic, prompt: "",
      keepsRecordings: true, takes: attempts,
      mimicReference: MimicReference(sourceName: "Copied reference", take: reference,
        sourceStart: 0, sourceEnd: reference.result.metrics.duration),
      mimicStyle: .listenAndRepeat, mimicAttemptStyles: [:])
    sessions = [session]
    print("Session folder has no style metadata; treating all WAV takes as one style.")
  }

  var pairCount = 0
  var identicalCount = 0
  for session in sessions {
    guard let reference = session.mimicReference?.take else { continue }
    for first in session.takes {
      let firstStyle = session.mimicAttemptStyles?[first.id] ?? session.mimicStyle
      for second in session.takes where second.id != first.id {
        let secondStyle = session.mimicAttemptStyles?[second.id] ?? session.mimicStyle
        guard firstStyle == secondStyle else { continue }
        pairCount += 1
        let target = CoachingPlanner.mimic(reference: reference, attempt: first).focus
        guard let target else {
          print("\(session.id) \(first.id) -> \(second.id): no-target")
          continue
        }
        let result = CoachingPlanner.evaluateRetry(
          reference: reference, attempt: second, pinnedTarget: target)
        let newGap = result.newGap.map { String(format: "%.3f", $0) } ?? "nil"
        print("\(session.id) \(first.id) -> \(second.id): \(target.kind.rawValue) \(target.word) "
          + "old=\(String(format: "%.3f", target.gap)) new=\(newGap) \(result.verdict.rawValue)")
      }
      if let target = CoachingPlanner.mimic(reference: reference, attempt: first).focus {
        let identical = CoachingPlanner.evaluateRetry(
          reference: reference, attempt: first, pinnedTarget: target)
        guard identical.verdict == .withinNoise,
          identical.verdictCopy == OneTargetRetryStrings.withinNoiseVerdict
        else {
          throw RetryVerdictCLIError.identicalTake(first.id, identical.verdict.rawValue)
        }
        identicalCount += 1
      }
    }
  }
  print("Ordered same-style pairs: \(pairCount)")
  print("Identical takes: \(identicalCount) about-the-same")
}

private enum RetryVerdictCLIError: Error {
  case identicalTake(UUID, String)
}

/// Exercises the actual SessionStore migration on disposable copies of a
/// support root. The generated backup filenames mirror the migration output.
func verifyCopiedLegacyLibraries(at input: URL) throws {
  struct LegacyDocument: Encodable {
    let schemaVersion: Int
    let sessions: [CoachingSession]
  }
  let manager = FileManager.default
  let source = try SessionStore(rootURL: input).load()
  guard !source.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
  for version in [1, 2] {
    let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("voicecoach-legacy-\(version)-\(UUID().uuidString)")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let sourceSessions = input.appendingPathComponent("Sessions", isDirectory: true)
    if manager.fileExists(atPath: sourceSessions.path) {
      try manager.copyItem(
        at: sourceSessions, to: root.appendingPathComponent("Sessions", isDirectory: true))
    }
    let backup = root.appendingPathComponent("session-library-v\(version)-backup.json")
    try JSONEncoder().encode(LegacyDocument(schemaVersion: version, sessions: source))
      .write(to: backup)
    let library = root.appendingPathComponent("session-library.json")
    try manager.copyItem(at: backup, to: library)
    let store = try SessionStore(rootURL: root)
    _ = try store.load()
    let loaded = try store.load()
    guard loaded.count == source.count,
      loaded.flatMap(\.takes).count == source.flatMap(\.takes).count,
      loaded.flatMap(\.takes).allSatisfy({
        $0.savedTarget == nil && manager.fileExists(atPath: $0.audioURL.path)
      }),
      loaded.allSatisfy({
        $0.mimicReference.map { manager.fileExists(atPath: $0.take.audioURL.path) } ?? true
      })
    else { throw CocoaError(.coderReadCorrupt) }
    print("v\(version) copied backup: loaded \(loaded.count) sessions, "
      + "\(loaded.flatMap(\.takes).count) takes, savedTarget=nil")
  }
  let current = try SessionStore(rootURL: input).load()
  guard current.flatMap(\.takes).allSatisfy({ $0.savedTarget == nil }) else {
    throw CocoaError(.coderReadCorrupt)
  }
  print("v3 current copy: loaded \(current.count) sessions, "
    + "\(current.flatMap(\.takes).count) takes, savedTarget=nil")
}
