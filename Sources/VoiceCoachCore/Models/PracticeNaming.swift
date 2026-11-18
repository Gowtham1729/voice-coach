import Foundation

/// Display titles for new practices. Titles are only cleaned when a practice is created;
/// stored names are never rewritten.
public enum PracticeNaming {
  /// A file name without encoding noise such as "(128k)" or "[320kbps]", with underscores
  /// read as spaces. Falls back to the input when cleaning would leave nothing.
  public static func cleaned(fileName: String) -> String {
    var text = fileName.replacingOccurrences(of: "_", with: " ")
    text = text.replacingOccurrences(
      of: #"\s*[\(\[]\s*\d+\s*(k|kbps|kb/s)\s*[\)\]]"#,
      with: "",
      options: [.regularExpression, .caseInsensitive]
    )
    text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? fileName : text
  }

  /// The opening words of a transcript, or nil when it has no words.
  public static func fromTranscript(_ text: String, maxWords: Int = 8) -> String? {
    let words = text.split(whereSeparator: \.isWhitespace)
    guard !words.isEmpty else { return nil }
    let excerpt = words.prefix(maxWords).joined(separator: " ")
    return words.count > maxWords ? "\(excerpt)…" : excerpt
  }
}
