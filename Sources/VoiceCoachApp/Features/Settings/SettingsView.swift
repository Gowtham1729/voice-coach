import SwiftUI
import VoiceCoachCore

private enum SettingsPane: String {
  case general
  case transcription
  case library
}

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot
  @AppStorage("voiceCoach.settingsPane") private var pane = SettingsPane.general
  @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmDelete = true
  @AppStorage("voiceCoach.hideTranscriptSnippets") private var hideTranscriptSnippets = false
  @AppStorage("voiceCoach.autoGenerateTitles") private var autoGenerateTitles = false
  @AppStorage("voiceCoach.rewriteInsightWording") private var rewriteInsightWording = false

  private var transcriptionBusy: Bool {
    model.systemTranscriptionStatus.isBusy
      || model.transcriptionSetupStatus.isBusy
      || model.isRecording
      || model.isAnalyzing
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
        InsightCopyGenerator.prewarmIfAvailable()
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
    }
    .frame(width: 480, height: 520)
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
        Toggle("On-device insight wording", isOn: $rewriteInsightWording)
          .onChange(of: rewriteInsightWording) { _, enabled in
            if enabled { InsightCopyGenerator.prewarmIfAvailable() }
          }
        if rewriteInsightWording {
          LabeledContent("Apple Intelligence", value: InsightCopyGenerator.status.settingsLabel)
        }
      } header: {
        Text("Insights")
      } footer: {
        Text(
          "Coaching decisions are deterministic. On supported devices, wording may be rewritten on device."
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
          Text("System").tag(TranscriptionEnginePreference.system)
          Text("Parakeet").tag(TranscriptionEnginePreference.parakeet)
        }
        .pickerStyle(.radioGroup)
        .disabled(busy)
      } footer: {
        Text(model.transcriptionEngine.settingsFooter)
      }

      transcriptionStatusSection(
        title: "System",
        status: systemStatus.title,
        footer: systemStatus.settingsFooter,
        emphasized: activeEngine == .system,
        progress: {
          if case .downloading = systemStatus {
            progressRow("Downloading…")
          }
        },
        actions: {
          if case .needsDownload = systemStatus {
            Button("Download Model…") {
              model.ensureSystemTranscriptionAssets()
            }
            .disabled(busy)
          }
        }
      )

      transcriptionStatusSection(
        title: "Parakeet",
        status: parakeetStatus.title,
        footer: parakeetStatus.settingsFooter,
        emphasized: activeEngine == .parakeet,
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
    emphasized: Bool = true,
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
    .opacity(emphasized ? 1.0 : 0.65)
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

      snapshotCard("Transcription", symbol: "waveform") {
        let isSystem = model.transcriptionEngine == .system
        Text(model.transcriptionEngine.title)
          .font(.body.weight(.medium))
        Text("System · \(model.systemTranscriptionStatus.title)")
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
      "On-device SpeechAnalyzer. Shared system models."
    case .parakeet:
      "Optional local Parakeet model (~714 MB)."
    }
  }
}

extension SystemTranscriptionStatus {
  fileprivate var settingsFooter: String {
    switch self {
    case .ready(let locale):
      "\(locale) · on-device"
    case .needsDownload(let locale):
      "Download the speech model for \(locale). Analysis still works without it."
    case .downloading(let locale):
      "Downloading \(locale)…"
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
