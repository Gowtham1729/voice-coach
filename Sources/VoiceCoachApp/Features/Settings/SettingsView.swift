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
          "Try features still being evaluated. Off by default; turning this off closes and clears experimental chats."
        )
      }
      if experimentalFeatures {
        Section {
          LabeledContent("Recording and Mimic chat", value: "Enabled")
          LabeledContent("Apple Intelligence", value: CoachingWordingGenerator.status.settingsLabel)
        } footer: {
          Text(
            "Open a recording or Mimic and choose Ask in the inspector. Replies run on this Mac. Chats are temporary and clear when you quit; only recent messages are included in follow-ups."
          )
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
      } header: {
        Text("Deleting")
      }

      Section {
        Toggle("Hide transcript snippets in Library", isOn: $hideTranscriptSnippets)
      } header: {
        Text("Library display")
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
          Text("Titles use on-device Apple Intelligence when enabled.")
          if autoGenerateTitles {
            Text(intelligenceStatus.settingsFooter)
          }
        }
      }

      Section {
        Toggle("Personalize exercises on device", isOn: $rewriteInsightWording)
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
          "Mimic comparisons include practice targets measured against the reference. Apple Intelligence can rephrase those exercises on this Mac."
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
            "Choose the spoken language here. Your Mac’s language stays the same. Saved sessions keep their speech language."
          )
        } else {
          Text(
            "Recognizes supported languages automatically. Japanese and other unsupported languages require Apple."
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
              Button("Download Language…") {
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
        LabeledContent("Mimics", value: "\(model.mimicSessions.count)")
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
      Text("Voice Coach Settings")
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
          Text("On-device insight wording")
          Spacer()
          Image(systemName: rewriteInsightWording ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(Studio.accent)
        }
        Text("Recordings stay on this Mac. Titles use Apple Intelligence when enabled.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(
          "Coaching decisions are deterministic. On supported devices, wording may be rewritten on device."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      snapshotCard("Experiments", symbol: "flask") {
        LabeledContent("Experimental features", value: experimentalFeatures ? "On" : "Off")
        Text("Optional chat for one recording or Mimic. On-device; temporary conversations.")
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
        LabeledContent("Mimics", value: "\(model.mimicSessions.count)")
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
      "On-device Apple speech. Download only the languages you use; models are shared with the system."
    case .parakeet:
      "Optional local model (~714 MB). Supports 25 European languages; Japanese is unsupported."
    }
  }
}

extension SystemTranscriptionStatus {
  fileprivate var settingsFooter: String {
    switch self {
    case .ready(let locale):
      "\(TranscriptionLanguagePreference.displayName(for: locale)) · on-device"
    case .needsDownload(let locale):
      "Download Apple’s speech model for \(TranscriptionLanguagePreference.displayName(for: locale)). Audio analysis and saving still work without it."
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
      "Optional. System transcription works without it."
    case .installing(let phase):
      phase.userFacingLabel
    case .failed(let message), .unsupported(let message):
      message
    }
  }
}
