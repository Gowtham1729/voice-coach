import Foundation
import VoiceCoachCore

/// One speakable line the chat can stay attached to.
struct SessionChatPassage: Identifiable, Equatable, Sendable {
  enum Origin: String, Sendable {
    case attempt
    case reference
  }

  let origin: Origin
  let index: Int
  let text: String

  var id: String { "\(origin.rawValue)-\(index)" }

  var menuTitle: String {
    let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard flat.count > 72 else { return flat }
    return String(flat.prefix(69)) + "…"
  }
}

enum SessionChatPassages {
  static func make(origin: SessionChatPassage.Origin, text: String?) -> [SessionChatPassage] {
    sentences(in: text).enumerated().map { index, sentence in
      SessionChatPassage(origin: origin, index: index, text: clip(sentence, limit: 500))
    }
  }

  static func sentences(in text: String?) -> [String] {
    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else { return [] }
    var results: [String] = []
    for line in trimmed.split(whereSeparator: \.isNewline) {
      let piece = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !piece.isEmpty else { continue }
      results.append(contentsOf: splitOnTerminators(piece))
    }
    return results
  }

  /// Maps a tapped transcript word back to its sentence. Word timings and the
  /// joined transcript usually move together; a text search covers the rest.
  static func sentence(containingWordAt index: Int, words: [TranscriptWord], text: String) -> String? {
    let sentences = sentences(in: text)
    guard words.indices.contains(index), !sentences.isEmpty else { return nil }
    var cursor = 0
    for sentence in sentences {
      let tokens = max(sentence.split(whereSeparator: \.isWhitespace).count, 1)
      let end = min(words.count, cursor + tokens)
      if (cursor..<end).contains(index) { return clip(sentence, limit: 500) }
      cursor = end
    }
    let needle = words[index].word.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return nil }
    return sentences.first { $0.localizedCaseInsensitiveContains(needle) }.map { clip($0, limit: 500) }
  }

  static func clip(_ text: String, limit: Int) -> String {
    let marker = " [excerpt; remainder omitted]"
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasSuffix(marker) { return trimmed }
    guard trimmed.count > limit else { return trimmed }
    return String(trimmed.prefix(limit)) + marker
  }

  private static func splitOnTerminators(_ text: String) -> [String] {
    var sentences: [String] = []
    var current = ""
    for character in text {
      current.append(character)
      if character == "." || character == "!" || character == "?" {
        let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sentence.isEmpty { sentences.append(sentence) }
        current = ""
      }
    }
    let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if !tail.isEmpty { sentences.append(tail) }
    return sentences.isEmpty ? [text] : sentences
  }
}

struct SessionChatReply: Equatable, Sendable {
  var answer: String
  var practiceLine: String?

  static let voiceBoundary = SessionChatReply(
    answer:
      "I only have the words from this take, so I can't judge how it sounds. Ask what a word means, or for a clearer line.",
    practiceLine: nil
  )

  static let languageNeeded = SessionChatReply(
    answer: "Which language should I translate into? For example, French or Spanish.",
    practiceLine: nil
  )

  init(answer: String, practiceLine: String?) {
    let cleanedAnswer = SessionChatAnswerCleaner.clean(answer)
    let cleanedLine = practiceLine.flatMap { SessionChatAnswerCleaner.usableLine($0) }
    if cleanedAnswer.isEmpty, let cleanedLine {
      self.answer = cleanedLine
      self.practiceLine = cleanedLine
    } else {
      self.answer = cleanedAnswer
      self.practiceLine = cleanedLine
    }
  }

  var answerRepeatsPracticeLine: Bool {
    guard let practiceLine else { return false }
    return folded(answer) == folded(practiceLine)
  }

  private func folded(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
  }
}

/// Drops a leading "I can't hear you" sentence. That phrase was a prompt echo, not an answer.
enum SessionChatAnswerCleaner {
  static func clean(_ raw: String) -> String {
    dropSchemaEcho(cleanApology(raw))
  }

  static func usableLine(_ raw: String) -> String? {
    let cleaned = stripQuotes(clean(raw))
    let folded = cleaned.lowercased()
    if cleaned.isEmpty { return nil }
    if ["[]", "[ ]", "empty", "none", "n/a", "null"].contains(folded) { return nil }
    return cleaned
  }

  private static func cleanApology(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let patterns = [
      #"(?i)^(?:i'm\s+|i am\s+)?sorry[,.]?\s+i can(?:not|'t) hear you[.!,]?\s*(?:but\s+)?"#,
      #"(?i)^i can(?:not|'t) hear (?:you|audio|the audio|your voice)[.!,]?\s*(?:but\s+)?"#,
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let range = NSRange(text.startIndex..., in: text)
      guard let match = regex.firstMatch(in: text, range: range), match.range.location == 0,
        let swiftRange = Range(match.range, in: text)
      else { continue }
      text = String(text[swiftRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return text
  }

  /// The small model sometimes writes the output field name into the answer.
  private static func dropSchemaEcho(_ raw: String) -> String {
    raw
      .components(separatedBy: .newlines)
      .filter { line in
        let folded = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !folded.hasPrefix("practiceline") && !folded.hasPrefix("practice line")
      }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func firstSentence(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let end = trimmed.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) else {
      return trimmed
    }
    return String(trimmed[...end])
  }

  static func stripQuotes(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'")]
    for (open, close) in pairs where text.first == open && text.last == close && text.count >= 2 {
      text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return text
  }
}

struct SessionChatRequest: Equatable, Sendable {
  var instructions: String
  var prompt: String
}

/// Each case is a separate instruction strategy. One shared prompt made the model
/// explain when it was asked to rewrite, and recite a hearing disclaimer.
enum SessionChatTask: Equatable, Sendable {
  case explain(String)
  case rephrase(String)
  case synonym(String)
  case translate(language: String, question: String)
  case practise(String)
  case ask(String)

  static let menuLanguages = ["French", "Spanish", "German", "Japanese", "Hindi", "Chinese"]

  var question: String {
    switch self {
    case .explain(let question), .rephrase(let question), .synonym(let question),
      .practise(let question), .ask(let question):
      question
    case .translate(_, let question):
      question
    }
  }

  var instructions: String {
    switch self {
    case .explain:
      """
      Define the word or phrase the question asks about, as it is used in the quoted line.
      Write two short sentences. Start with the meaning.
      If the word is likely a mis-hearing, name the word you think was intended.
      """
    case .rephrase, .synonym:
      """
      Rewrite the quoted line so a person would say it more naturally in conversation.
      Keep the same meaning and the same facts.
      Put the rewritten line first, in quotation marks, then one short sentence on what changed.
      practiceLine is that rewritten line with no quotation marks.
      """
    case .translate(let language, _):
      """
      Translate the quoted line into \(language).
      answer is the \(language) sentence only.
      practiceLine is the same \(language) sentence.
      """
    case .practise:
      """
      Give one concrete way to practise saying the quoted line out loud.
      Name the idea to stress and where a short pause helps. Use only the words in the line.
      practiceLine is the line to say. Clean grammar only if the quoted line is ungrammatical.
      """
    case .ask:
      """
      Answer the question about the quoted line in two or three plain sentences.
      Start with the answer. Stay under 60 words.
      If a speakable line would help, put only that sentence in practiceLine.
      """
    }
  }
}

enum SessionChatRoute: Equatable, Sendable {
  case model(SessionChatTask)
  case local(SessionChatReply)
}

/// Decides whether a typed question should reach the model. Voice judgments stay
/// here so the model is never told to talk about hearing.
enum SessionChatRouter {
  static func route(_ question: String) -> SessionChatRoute {
    let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
    let folded = text.lowercased()
    if isVoiceJudgment(folded) { return .local(.voiceBoundary) }
    if isTranslate(folded) {
      guard let language = language(in: folded) else { return .local(.languageNeeded) }
      return .model(.translate(language: language, question: text))
    }
    if isRephrase(folded) { return .model(.rephrase(text)) }
    if isPractise(folded) { return .model(.practise(text)) }
    if isExplain(folded) { return .model(.explain(text)) }
    return .model(.ask(text))
  }

  static func language(in question: String) -> String? {
    let folded = question.lowercased()
    for language in catalog {
      for alias in language.aliases {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: alias))\\b"
        if folded.range(of: pattern, options: .regularExpression) != nil { return language.name }
      }
    }
    return nil
  }

  private static func isVoiceJudgment(_ text: String) -> Bool {
    let markers = [
      "can you hear", "can't you hear", "cannot hear", "can't hear me",
      "do i sound", "how do i sound", "how did i sound", "did i sound",
      "how does my voice", "does my voice", "my voice sound",
      "my accent", "my pronunciation", "am i pronouncing", "pronounce this",
      "sound confident", "sound nervous", "sound anxious", "sound natural",
      "sound emotional", "sound good", "sound bad", "sound happy", "sound sad",
      "was i confident", "am i confident",
    ]
    return markers.contains { text.contains($0) }
  }

  private static func isTranslate(_ text: String) -> Bool {
    if text.contains("translate") || text.contains("translation") { return true }
    guard let language = language(in: text)?.lowercased() else { return false }
    return text.contains("in \(language)") || text.contains("into \(language)")
      || text.contains("to \(language)")
  }

  private static func isRephrase(_ text: String) -> Bool {
    [
      "another way", "more natural", "rephrase", "alternative", "rewrite", "clearer", "how else",
      "synonym", "another word",
    ].contains { text.contains($0) }
  }

  private static func isPractise(_ text: String) -> Bool {
    text.contains("practise") || text.contains("practice") || text.contains("help me say")
      || text.contains("how should i say") || text.contains("how do i say")
  }

  private static func isExplain(_ text: String) -> Bool {
    text.contains("what does") || text.contains("meaning") || text.contains("define")
      || text.contains("explain") || text.contains("what is")
  }

  private static let catalog: [(name: String, aliases: [String])] = [
    ("French", ["french", "français"]),
    ("Spanish", ["spanish", "español"]),
    ("German", ["german", "deutsch"]),
    ("Italian", ["italian", "italiano"]),
    ("Portuguese", ["portuguese", "português"]),
    ("Japanese", ["japanese"]),
    ("Korean", ["korean"]),
    ("Chinese", ["chinese", "mandarin"]),
    ("Hindi", ["hindi"]),
    ("Arabic", ["arabic"]),
    ("English", ["english"]),
  ]
}

enum SessionChatPromptComposer {
  static func make(
    context: SessionChatContext,
    focus: String?,
    history: [SessionChatConversation.Exchange],
    task: SessionChatTask
  ) -> SessionChatRequest {
    let quoted = SessionChatPassages.clip(focus ?? context.fallbackQuote, limit: 500)
    var lines = ["Quoted line: \(quoted)"]
    if case .ask = task {
      let excerpt = context.transcriptExcerpt
      if excerpt != quoted && excerpt != SessionChatContext.missingTranscript {
        lines.append("Transcript excerpt: \(excerpt)")
      }
      // Buttons stay on the quoted line. Only a free-form follow-up needs the last replies.
      let recent = history.suffix(2)
      if !recent.isEmpty {
        lines.append("Earlier:")
        for exchange in recent {
          lines.append("Question: \(SessionChatPassages.clip(exchange.question, limit: 200))")
          lines.append("Answer: \(SessionChatPassages.clip(exchange.answer, limit: 300))")
        }
      }
    }
    lines.append("Question: \(task.question)")
    return SessionChatRequest(instructions: task.instructions, prompt: lines.joined(separator: "\n"))
  }
}
