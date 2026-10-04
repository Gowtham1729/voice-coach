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
        Section("Transcript") {
          Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        Section {
          Picker("Translate into", selection: $target) {
            ForEach(languages, id: \.code) { language in Text(language.name).tag(language.code) }
          }.disabled(isTranslating)
          Text("Translates on this Mac. Some languages need a download.")
            .font(.caption).foregroundStyle(.secondary)
          Button("Translate", action: translate).disabled(isTranslating)
          if isTranslating { ProgressView("Translating…").controlSize(.small) }
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
          "Couldn’t translate this text. Try another language or check downloaded models in System Settings."
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
