import AppKit
import SwiftUI

/// Install state of one Sound comparison engine, in the Parakeet row's words (FR-23).
enum SoundEngineStatus: Equatable {
  case notInstalled
  case ready
  /// Files from another engine version.
  case needsAttention
  /// Intel Mac (D4).
  case unavailable

  var title: String {
    switch self {
    case .notInstalled: "Not installed"
    case .ready: "Ready"
    case .needsAttention: "Needs attention"
    case .unavailable: "Unavailable"
    }
  }

  var footer: String {
    switch self {
    case .notInstalled: "Optional. Runs on this Mac."
    case .ready: "On this Mac only."
    case .needsAttention: "These files are for another version of Ichido. Install it again."
    case .unavailable: "Needs a Mac with Apple silicon."
    }
  }
}

extension AppModel {
  func soundEngineStatus(_ id: String) -> SoundEngineStatus {
    #if arch(arm64)
    guard let install = soundEngines.first(where: { $0.id == id }) else { return .notInstalled }
    return install.isCurrent ? .ready : .needsAttention
    #else
    return .unavailable
    #endif
  }
}

/// Settings → Transcription → Sound comparison: one row per listed engine, and a picker for
/// the active engine when two or more are ready (FR-23, FR-25, FR-26).
struct SoundComparisonSettingsSections: View {
  @EnvironmentObject private var model: AppModel
  @State private var installing: SoundEngineDescriptor?
  @State private var pendingDelete: SoundEngineDescriptor?

  private var engines: [SoundEngineDescriptor] {
    SoundEngineCatalog.visible(showsExperimental: model.showsExperimentalSoundEngines)
  }

  private var readyEngines: [SoundEngineDescriptor] {
    engines.filter { model.soundEngineStatus($0.id) == .ready }
  }

  var body: some View {
    if !engines.isEmpty {
      Section {
        if readyEngines.count >= 2 {
          Picker("Active engine", selection: activeEngine) {
            ForEach(readyEngines) { engine in
              Text("\(engine.name) · \(size(of: engine))").tag(engine.id)
            }
          }
          .pickerStyle(.radioGroup)
        } else {
          LabeledContent(
            "Active engine",
            value: readyEngines.first.map { $0.name } ?? "None installed")
        }
      } header: {
        Text("Sound comparison")
      } footer: {
        Text(
          "Compares each take with its reference, sound by sound, on this Mac. Review shows up to 3 words that sounded different, and you can listen to both. It does not grade your accent."
        )
      }

      ForEach(engines) { engine in
        engineSection(engine)
      }
      .confirmationDialog(
        "Delete the \(pendingDelete?.name ?? "") engine?",
        isPresented: Binding(
          get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
        presenting: pendingDelete
      ) { engine in
        Button("Delete engine", role: .destructive) {
          model.removeSoundEngine(engine.id)
        }
      } message: { engine in
        Text(
          "Deletes its files (\(size(of: engine))) and the sound results it made. Audio, transcripts, and other analysis stay."
        )
      }
    }
  }

  private func engineSection(_ engine: SoundEngineDescriptor) -> some View {
    let status = model.soundEngineStatus(engine.id)
    return Section {
      LabeledContent("Status", value: status.title)
      LabeledContent("Size", value: size(of: engine))
      switch status {
      case .ready, .needsAttention:
        if status == .needsAttention {
          installButton(engine, title: "Install again…")
        }
        Button("Delete…", role: .destructive) { pendingDelete = engine }
          .disabled(!model.soundComparisonRunning.isEmpty)
      case .notInstalled:
        installButton(engine, title: "Install…")
      case .unavailable:
        EmptyView()
      }
    } header: {
      HStack(spacing: 6) {
        Text("Sound comparison · \(engine.name)")
        if engine.tier == .experimental {
          ExperimentalBadge()
        }
      }
    } footer: {
      Text(status.footer)
    }
  }

  private func installButton(_ engine: SoundEngineDescriptor, title: String) -> some View {
    Button(title) { installing = engine }
      .popover(
        isPresented: Binding(
          get: { installing == engine }, set: { if !$0 { installing = nil } }),
        arrowEdge: .trailing
      ) {
        SoundEngineInstallInstructions(engine: engine) {
          model.refreshSoundEngines()
          installing = nil
        }
      }
  }

  private var activeEngine: Binding<String> {
    Binding(
      get: { model.activeSoundEngineID ?? readyEngines.first?.id ?? "" },
      set: { model.setActiveSoundEngine($0) })
  }

  private func size(of engine: SoundEngineDescriptor) -> String {
    if let install = model.soundEngines.first(where: { $0.id == engine.id }) {
      return SoundEngineDescriptor.formattedSize(install.sizeBytes)
    }
    return "About \(SoundEngineDescriptor.formattedSize(engine.approximateSizeBytes))"
  }
}

/// There is no hosted download yet, so Install shows the exact command to run (FR-24: the size
/// comes first, and nothing is left behind if it fails, because the script stages its work).
private struct SoundEngineInstallInstructions: View {
  let engine: SoundEngineDescriptor
  let onCheckAgain: () -> Void
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Install \(engine.name) (about \(SoundEngineDescriptor.formattedSize(engine.approximateSizeBytes)))")
        .font(.headline)
      Text("In Terminal, from the Ichido source folder, run:")
        .font(.callout)
      Text(engine.installCommand)
        .font(.callout.monospaced())
        .textSelection(.enabled)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
      Text(
        "It downloads the model weights from Hugging Face and converts them on this Mac. It needs uv and git. Your audio stays on this Mac."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      HStack {
        Button(copied ? "Copied" : "Copy command") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(engine.installCommand, forType: .string)
          copied = true
        }
        Spacer()
        Button("Check again", action: onCheckAgain)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(16)
    .frame(width: 340)
  }
}

struct ExperimentalBadge: View {
  var body: some View {
    Text("Experimental")
      .font(.caption2.weight(.semibold))
      .textCase(nil)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(.quaternary.opacity(0.6), in: Capsule())
  }
}

enum SoundComparisonSettingsCopy {
  static let experimentsFooter =
    "Lists Sound comparison engines in Transcription. They rarely mark words you said the same way as your reference, but they miss many real differences."
}

/// Static Sound comparison rows for the Settings snapshot used by layout previews.
struct SoundComparisonSnapshotRows: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    let engines = SoundEngineCatalog.visible(showsExperimental: model.showsExperimentalSoundEngines)
    let ready = engines.filter { model.soundEngineStatus($0.id) == .ready }
    if ready.count >= 2 {
      LabeledContent(
        "Active engine",
        value: SoundEngineCatalog.descriptor(model.activeSoundEngineID ?? "")?.name ?? "")
    }
    ForEach(engines) { engine in
      HStack(spacing: 6) {
        Text(engine.name)
        ExperimentalBadge()
        Spacer()
        Text(model.soundEngineStatus(engine.id).title)
          .foregroundStyle(.secondary)
      }
    }
    Text("Up to 3 words that sounded different from your reference. It does not grade your accent.")
      .font(.caption)
      .foregroundStyle(.secondary)
  }
}
