import Foundation

public struct MimicWordPair: Sendable, Equatable {
  public let referenceIndex: Int
  public let attemptIndex: Int
  public let word: String
  public let reference: TranscriptWord
  public let attempt: TranscriptWord
  public let referencePitch: Double?
  public let attemptPitch: Double?
  public let referenceEnergy: Double?
  public let attemptEnergy: Double?
}

/// One Reference word and one take word left unmatched between the same two matched words.
public struct MimicHeardDifference: Sendable, Equatable {
  public let referenceIndex: Int
  public let attemptIndex: Int
  public let reference: TranscriptWord
  public let attempt: TranscriptWord
}

public enum MimicAlignmentStatus: String, Sendable, Equatable {
  case ok
  case missingTranscript = "missing_transcript"
  case tooManyWords = "too_many_words"
  case lowCoverage = "low_coverage"
  case poorSnr = "poor_snr"
  case clipping
}

public struct MimicComparison: Sendable, Equatable {
  public let pairs: [MimicWordPair]
  public let status: MimicAlignmentStatus
  /// Shown only when the alignment is reliable, at most three. Never a Practice next target.
  public let heardDifferently: [MimicHeardDifference]

  public var correspondenceReliable: Bool { status == .ok }

  public static func compare(reference: PracticeSession, attempt: PracticeSession) -> Self {
    guard let referenceWords = reference.transcription?.words,
      let attemptWords = attempt.transcription?.words,
      !referenceWords.isEmpty, !attemptWords.isEmpty
    else { return empty(.missingTranscript) }
    guard referenceWords.count <= 160, attemptWords.count <= 160
    else { return empty(.tooManyWords) }

    let left = referenceWords.map { normalized($0.word) }
    let right = attemptWords.map { normalized($0.word) }
    var lengths = Array(
      repeating: Array(repeating: 0, count: right.count + 1), count: left.count + 1)
    for i in 1...left.count {
      for j in 1...right.count {
        if !left[i - 1].isEmpty && left[i - 1] == right[j - 1] {
          lengths[i][j] = lengths[i - 1][j - 1] + 1
        } else {
          lengths[i][j] = max(lengths[i - 1][j], lengths[i][j - 1])
        }
      }
    }
    var indices: [(Int, Int)] = []
    var i = left.count
    var j = right.count
    while i > 0 && j > 0 {
      if !left[i - 1].isEmpty && left[i - 1] == right[j - 1] {
        indices.append((i - 1, j - 1))
        i -= 1
        j -= 1
      } else if lengths[i - 1][j] >= lengths[i][j - 1] {
        i -= 1
      } else {
        j -= 1
      }
    }
    indices.reverse()

    let pairs = indices.map { a, b in
      MimicWordPair(
        referenceIndex: a, attemptIndex: b, word: referenceWords[a].word,
        reference: referenceWords[a], attempt: attemptWords[b],
        referencePitch: reference.words.indices.contains(a)
          ? reference.words[a].pitch.relativeMedianSemitones : nil,
        attemptPitch: attempt.words.indices.contains(b)
          ? attempt.words[b].pitch.relativeMedianSemitones : nil,
        referenceEnergy: reference.words.indices.contains(a)
          ? reference.words[a].loudness.relativeMeanDB : nil,
        attemptEnergy: attempt.words.indices.contains(b)
          ? attempt.words[b].loudness.relativeMeanDB : nil
      )
    }

    let coverageOK =
      indices.count >= 2
      && Double(indices.count) / Double(max(left.count, right.count)) >= 0.75
    let clippingOK =
      attempt.result.metrics.clippingPercent < 3
      && reference.result.metrics.clippingPercent < 3
    let snrOK =
      attempt.result.metrics.snrDB >= 6
      && reference.result.metrics.snrDB >= 6

    let status: MimicAlignmentStatus
    if !coverageOK {
      status = .lowCoverage
    } else if !clippingOK {
      status = .clipping
    } else if !snrOK {
      status = .poorSnr
    } else {
      status = .ok
    }
    var heardDifferently: [MimicHeardDifference] = []
    if status == .ok {
      for (before, after) in zip(indices, indices.dropFirst())
      where after.0 - before.0 == 2 && after.1 - before.1 == 2 {
        let a = before.0 + 1
        let b = before.1 + 1
        guard !left[a].isEmpty, !right[b].isEmpty else { continue }
        heardDifferently.append(
          .init(
            referenceIndex: a, attemptIndex: b,
            reference: referenceWords[a], attempt: attemptWords[b]))
        if heardDifferently.count == 3 { break }
      }
    }
    return .init(pairs: pairs, status: status, heardDifferently: heardDifferently)
  }

  private static func empty(_ status: MimicAlignmentStatus) -> Self {
    .init(pairs: [], status: status, heardDifferently: [])
  }

  private static func normalized(_ word: String) -> String {
    word.lowercased().unicodeScalars
      .filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
      .map(String.init).joined()
  }
}
