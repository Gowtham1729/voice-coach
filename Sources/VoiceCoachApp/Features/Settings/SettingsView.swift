import SwiftUI
import VoiceCoachCore

private enum SettingsPane: String {
  case general
  case transcription
  case library
  case experiments
}

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot
  @AppStorage("voiceCoach.settingsPane") private var pane = SettingsPane.general
  @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmDelete = true
  @AppStorage("voiceCoach.hideTranscriptSnippets") private var hideTranscriptSnippets = false
  @AppStorage("voiceCoach.autoGenerateTitles") private var autoGenerateTitles = false
  @AppStorage(InsightWordingPreference.storageKey) private var rewriteInsightWording =
    InsightWordingPreference.default

  @AppStorage(ExperimentalFeaturesPreference.storageKey) private var experimentalFeatures =
    ExperimentalFeaturesPreference.default

  private var transcriptionBusy: Bool {
    model.systemTranscriptionStatus.isBusy
      || model.transcriptionSetupStatus.isBusy
      || model.isRecording
      || model.isAnalyzing
      || model.mimicIsPreparing
      || model.isCheckingSpeechLanguages
  }

  var body: some View {
    Group {
      if snapshot {
        snapshotSettings
      } else {
        liveSettings
      }
    }
    .onAppear {
      model.refreshTranscriptionSetupStatus()
      model.refreshSystemTranscriptionStatus()
      if autoGenerateTitles {
        SmartTitleGenerator.prewarmIfAvailable()
      }
      if rewriteInsightWording {
        CoachingWordingGenerator.prewarmIfAvailable()
      }
    }
  }

  private var liveSettings: some View {
    TabView(selection: $pane) {
      Tab("General", systemImage: "gearshape", value: SettingsPane.general) {
        generalPane
      }
      Tab("Transcription", systemImage: "waveform", value: SettingsPane.transcription) {
        transcriptionPane
      }
      Tab("Library", systemImage: "internaldrive", value: SettingsPane.library) {
        libraryPane
      }
      Tab("Experiments", systemImage: "flask", value: SettingsPane.experiments) {
        experimentsPane
      }
    }
    .frame(width: 480, height: 520)
  }

  private var experimentsPane: some View {
    Form {
      Section {
        Toggle("Enable experimental features", isOn: $experimentalFeatures)
          .onChange(of: experimentalFeatures) { _, enabled in
            model.noteExperimentalFeaturesChanged()
            if !enabled { model.clearExperimentalChats() }
          }
      } footer: {
        Text(
          "Turning this off clears all Words chats."
        )
      }
      if experimentalFeatures {
        Section {
          LabeledContent("Words", value: "Enabled")
          LabeledContent("Apple Intelligence", value: CoachingWordingGenerator.status.settingsLabel)
        } footer: {
          VStack(alignment: .leading, spacing: 4) {
            Text("Choose Words beside a recording or reference to explore its transcript.")
            Text("Uses Apple Intelligence on this Mac. Chats clear when you quit.")
            Text("Replies can be wrong. Words can’t hear or evaluate your audio.")
          }
        }
      }
    }
    .settingsPaneChrome()
  }

  private var generalPane: some View {
    let intelligenceStatus = SmartTitleGenerator.status
    return Form {
      Section {
        Toggle("Confirm before deleting", isOn: $confirmDelete)
        Toggle("Hide transcript snippets in Library", isOn: $hideTranscriptSnippets)
      } header: {
        Text("Library")
      }

      Section {
        Toggle("Name recordings from transcripts", isOn: $autoGenerateTitles)
          .onChange(of: autoGenerateTitles) { _, enabled in
            if enabled { SmartTitleGenerator.prewarmIfAvailable() }
          }
        if autoGenerateTitles {
          LabeledContent("Apple Intelligence", value: intelligenceStatus.settingsLabel)
        }
      } header: {
        Text("Naming")
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          Text("Uses Apple Intelligence on this Mac.")
          if autoGenerateTitles && intelligenceStatus != .available {
            Text(intelligenceStatus.settingsFooter)
          }
        }
      }

      Section {
        Toggle("Rephrase practice exercises", isOn: $rewriteInsightWording)
          .onChange(of: rewriteInsightWording) { _, enabled in
            if enabled {
              CoachingWordingGenerator.prewarmIfAvailable()
              model.rescheduleInsightWordingForSelection()
            }
          }
        if rewriteInsightWording {
          LabeledContent("Apple Intelligence", value: CoachingWordingGenerator.status.settingsLabel)
        }
      } header: {
        Text("Practice next")
      } footer: {
        Text(
          "Apple Intelligence rephrases exercises on this Mac. Measured targets stay the same."
        )
      }
    }
    .settingsPaneChrome()
  }

  private var transcriptionPane: some View {
    let systemStatus = model.systemTranscriptionStatus
    let parakeetStatus = model.transcriptionSetupStatus
    let busy = transcriptionBusy
    let activeEngine = model.transcriptionEngine

    return Form {
      Section {
        Picker("Engine", selection: engineSelection) {
          Text("Apple (recommended)").tag(TranscriptionEnginePreference.system)
          Text("Parakeet").tag(TranscriptionEnginePreference.parakeet)
        }
        .pickerStyle(.radioGroup)
        .disabled(busy)
      } footer: {
        Text(model.transcriptionEngine.settingsFooter)
      }

      Section {
        SpeechLanguagePicker()
      } footer: {
        if activeEngine == .system {
          Text(
            "Applies to new recordings and references. Existing recordings keep their language."
          )
        } else {
          Text(
            "Detects supported languages automatically. For Japanese, choose Apple."
          )
        }
      }

      if activeEngine == .system {
        transcriptionStatusSection(
          title: "Apple speech model",
          status: systemStatus.title,
          footer: systemStatus.settingsFooter,
          progress: {
            if case .downloading = systemStatus {
              progressRow("Downloading…")
            }
          },
          actions: {
            if case .needsDownload = systemStatus {
              Button("Download language…") {
                model.ensureSystemTranscriptionAssets()
              }
              .disabled(busy)
            }
          }
        )
      } else {
        transcriptionStatusSection(
          title: "Parakeet (optional)",
          status: parakeetStatus.title,
          footer: parakeetStatus.settingsFooter,
          progress: {
            if case .installing(let phase) = parakeetStatus {
              progressRow(phase.userFacingLabel)
            }
          },
          actions: {
            parakeetButtons(status: parakeetStatus, busy: busy)
          }
        )
      }
    }
    .settingsPaneChrome()
  }

  private var libraryPane: some View {
    Form {
      Section {
        LabeledContent("Recordings", value: "\(model.userRecordedTakeCount)")
        LabeledContent("Minutes recorded", value: vcNumber(model.userRecordedDuration / 60, 1))
        LabeledContent("Imported", value: "\(model.importedTakeCount)")
        LabeledContent("Practice", value: "\(model.mimicSessions.count)")
        Button("Show in Finder…", systemImage: "folder", action: model.revealStorage)
      } footer: {
        VStack(alignment: .leading, spacing: 6) {
          Text("Audio and transcripts stay in this folder.")
          Text(model.storageLocation.path)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .lineLimit(2)
            .truncationMode(.middle)
        }
      }

      if !model.emptyLegacySessions.isEmpty {
        Section {
          Button("Remove \(model.emptyLegacySessions.count) unused folders") {
            model.cleanupEmptyLegacySessions()
          }
        }
      }
    }
    .settingsPaneChrome()
  }

  private var engineSelection: Binding<TranscriptionEnginePreference> {
    Binding(
      get: { model.transcriptionEngine },
      set: { model.setTranscriptionEngine($0) }
    )
  }

  private func transcriptionStatusSection<Progress: View, Actions: View>(
    title: String,
    status: String,
    footer: String,
    @ViewBuilder progress: () -> Progress,
    @ViewBuilder actions: () -> Actions
  ) -> some View {
    Section {
      LabeledContent("Status", value: status)
      progress()
      actions()
    } header: {
      Text(title)
    } footer: {
      Text(footer)
        .textSelection(.enabled)
    }
  }

  private func progressRow(_ label: String) -> some View {
    HStack(spacing: 8) {
      ProgressView().controlSize(.small)
      Text(label).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func parakeetButtons(status: TranscriptionSetupStatus, busy: Bool) -> some View {
    switch status {
    case .ready:
      Button("Check for Updates…", action: model.startTranscriptionSetup)
        .disabled(busy)
      Button("Show in Finder…", systemImage: "folder", action: model.revealTranscriptionInstall)
    case .unsupported:
      EmptyView()
    case .missing, .failed, .installing:
      Button(status.isBusy ? "Downloading…" : "Download… (~714 MB)") {
        model.startTranscriptionSetup()
      }
      .disabled(busy)
    }
  }

  private var snapshotSettings: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Ichido Settings")
        .font(.title2.weight(.semibold))

      snapshotCard("General", symbol: "gearshape") {
        HStack {
          Text("Confirm before deleting")
          Spacer()
          Image(systemName: confirmDelete ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(Studio.accent)
        }
        HStack {
          Text("Name recordings from transcripts")
          Spacer()
          Image(systemName: autoGenerateTitles ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(Studio.accent)
        }
        if autoGenerateTitles {
          HStack {
            Text("Apple Intelligence")
            Spacer()
            Text(SmartTitleGenerator.status.settingsLabel)
              .foregroundStyle(.secondary)
          }
        }
        HStack {
          Text("Rephrase practice exercises")
          Spacer()
          Image(systemName: rewriteInsightWording ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(Studio.accent)
        }
        Text("Titles use Apple Intelligence on this Mac when enabled.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(
          "Apple Intelligence rephrases exercises on this Mac. Measured targets stay the same."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      snapshotCard("Experiments", symbol: "flask") {
        LabeledContent("Experimental features", value: experimentalFeatures ? "On" : "Off")
        Text("Words explores your transcript on this Mac. Chats clear when you quit.")
          .font(.caption).foregroundStyle(.secondary)
      }

      snapshotCard("Transcription", symbol: "waveform") {
        let isSystem = model.transcriptionEngine == .system
        Text(model.transcriptionEngine.title)
          .font(.body.weight(.medium))
        LabeledContent(
          "Speech language",
          value: isSystem
            ? TranscriptionLanguagePreference.displayName(for: model.transcriptionLocale.identifier)
            : "Automatic")
        Text("Apple · \(model.systemTranscriptionStatus.title)")
          .font(.caption)
          .foregroundStyle(isSystem ? .primary : .secondary)
          .opacity(isSystem ? 1.0 : 0.65)
        Text("Parakeet · \(model.transcriptionSetupStatus.title)")
          .font(.caption)
          .foregroundStyle(!isSystem ? .primary : .secondary)
          .opacity(!isSystem ? 1.0 : 0.65)
      }

      snapshotCard("Library", symbol: "internaldrive") {
        LabeledContent("Recordings", value: "\(model.userRecordedTakeCount)")
        LabeledContent("Imported", value: "\(model.importedTakeCount)")
        LabeledContent("Practice", value: "\(model.mimicSessions.count)")
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Studio.background)
  }

  private func snapshotCard<Content: View>(
    _ title: String,
    symbol: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: symbol)
        .font(.headline)
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .desktopPanel()
  }
}

extension View {
  fileprivate func settingsPaneChrome() -> some View {
    formStyle(.grouped)
      .contentMargins(.top, 8, for: .scrollContent)
      .contentMargins(.bottom, 12, for: .scrollContent)
      .padding(.top, -6)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

extension TranscriptionEnginePreference {
  fileprivate var settingsFooter: String {
    switch self {
    case .system:
      "Transcribes on this Mac using Apple’s speech models."
    case .parakeet:
      "Transcribes on this Mac. Supports 25 European languages; download is about 714 MB."
    }
  }
}

extension SystemTranscriptionStatus {
  fileprivate var settingsFooter: String {
    switch self {
    case .ready(let locale):
      "\(TranscriptionLanguagePreference.displayName(for: locale)) · on-device"
    case .needsDownload(let locale):
      "Download \(TranscriptionLanguagePreference.displayName(for: locale)) for transcripts. You can still record and review audio without it."
    case .downloading(let locale):
      "Downloading \(TranscriptionLanguagePreference.displayName(for: locale))…"
    case .unavailable(let message):
      message
    }
  }
}

extension TranscriptionSetupStatus {
  fileprivate var settingsFooter: String {
    switch self {
    case .ready(_, let modelID):
      "\(modelID) · local only"
    case .missing:
      "Download Parakeet to use it, or choose Apple above."
    case .installing(let phase):
      phase.userFacingLabel
    case .failed(let message), .unsupported(let message):
      message
    }
  }
}
