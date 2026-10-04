import SwiftUI
import VoiceCoachCore

struct SpeechLanguagePicker: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    if model.transcriptionEngine == .system {
      appleLanguagePicker
    } else {
      LabeledContent("Speech language", value: "Automatic")
        .help("Parakeet recognizes 25 European languages automatically. Japanese is unsupported.")
    }
  }

  private var appleLanguagePicker: some View {
    Picker(
      "Speech language",
      selection: Binding(
        get: { model.transcriptionLocaleIdentifier },
        set: { model.setTranscriptionLanguage($0) }
      )
    ) {
      Text(
        "Mac language (\(TranscriptionLanguagePreference.displayName(for: Locale.current.identifier)))"
      )
      .tag("")
      if !model.transcriptionLocaleIdentifier.isEmpty,
        !model.supportedSpeechLocales.contains(model.transcriptionLocaleIdentifier)
      {
        Text(TranscriptionLanguagePreference.displayName(for: model.transcriptionLocaleIdentifier))
          .tag(model.transcriptionLocaleIdentifier)
      }
      ForEach(model.supportedSpeechLocales, id: \.self) { identifier in
        Text(TranscriptionLanguagePreference.displayName(for: identifier)).tag(identifier)
      }
    }
    .disabled(
      model.isRecording || model.isAnalyzing || model.mimicIsPreparing
        || model.systemTranscriptionStatus.isBusy || model.isCheckingSpeechLanguages
    )
    .help("Choose the language spoken in new recordings and practice references.")
  }
}
