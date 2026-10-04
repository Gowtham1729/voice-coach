import AppKit
import SwiftUI
@preconcurrency import Translation

/// TranslationSession processes text on-device. The system Translate overlay
/// can offer cloud processing on newer macOS releases, so don't use it here.
struct SessionChatTranslationSheet: View {
  let text: String
  @Environment(\.dismiss) private var dismiss
  @State private var target = "en"
  @State private var configuration: TranslationSession.Configuration?
  @State private var translatedText = ""
  @State private var errorMessage: String?
  @State private var isTranslating = false
  @State private var copied = false

  private let languages: [(code: String, name: String)] = [
    ("en", "English"), ("fr", "French"), ("es", "Spanish"), ("de", "German"),
    ("it", "Italian"), ("pt", "Portuguese"), ("ja", "Japanese"), ("ko", "Korean"),
    ("zh", "Chinese"), ("hi", "Hindi"), ("ar", "Arabic"),
  ]

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section("Selected text") {
          Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        Section {
          Picker("Translate into", selection: $target) {
            ForEach(languages, id: \.code) { language in Text(language.name).tag(language.code) }
          }.disabled(isTranslating)
          Text("Text is translated on this Mac. macOS may ask to download language models.")
            .font(.caption).foregroundStyle(.secondary)
          Button("Translate", action: translate).disabled(isTranslating)
          if isTranslating { ProgressView("Translating on this Mac…").controlSize(.small) }
        }
        if !translatedText.isEmpty {
          Section("Translation") {
            Text(translatedText).textSelection(.enabled).fixedSize(
              horizontal: false, vertical: true)
            Button(copied ? "Copied" : "Copy translation") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(translatedText, forType: .string)
              copied = true
            }
          }
        }
        if let errorMessage {
          Text(errorMessage).foregroundStyle(.secondary).fixedSize(
            horizontal: false, vertical: true)
        }
      }.formStyle(.grouped)
      Divider()
      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }.padding(16)
    }
    .frame(width: 500, height: 520)
    .translationTask(configuration) { session in
      do {
        let response = try await session.translate(text)
        try Task.checkCancellation()
        translatedText = response.targetText
      } catch is CancellationError {
        return
      } catch {
        errorMessage =
          "Translation isn't available for these languages yet. Check the language pair or downloaded models in System Settings."
      }
      isTranslating = false
    }
    .onChange(of: target) { _, _ in
      translatedText = ""
      errorMessage = nil
      copied = false
    }
  }

  private func translate() {
    isTranslating = true
    translatedText = ""
    errorMessage = nil
    copied = false
    if configuration == nil {
      configuration = .init(target: Locale.Language(identifier: target))
    } else if configuration?.target == Locale.Language(identifier: target) {
      configuration?.invalidate()
    } else {
      configuration = .init(target: Locale.Language(identifier: target))
    }
  }
}
