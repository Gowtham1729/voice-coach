import SwiftUI
import VoiceCoachCore
import VoiceCoachSession

struct MimicWorkspace: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot

  var body: some View {
    Group {
      if model.mimicWorkspaceMode == .analysis, model.selectedTake != nil {
        analysisLayout
      } else {
        practiceCompareLayout
      }
    }
  }

  private var analysisLayout: some View {
    VStack(spacing: 0) {
      if let session = model.selectedSession {
        heading(session)
          .padding(.horizontal, 20)
          .padding(.top, 20)
          .padding(.bottom, 8)
          .frame(maxWidth: 1050, alignment: .leading)
          .frame(maxWidth: .infinity, alignment: .top)
      }
      TakeView(embedded: true)
    }
  }

  private var practiceCompareLayout: some View {
    VStack(spacing: 0) {
      StudioScroll {
        if let session = model.selectedSession, let reference = session.mimicReference {
          VStack(alignment: .leading, spacing: 18) {
            heading(session)
            referenceStrip(reference)
            if let notice = model.transcriptionNotice {
              Label(notice, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            if model.mimicWorkspaceMode == .compare, let attempt = model.selectedTake {
              MimicComparisonView(
                reference: reference.take, attempt: attempt,
                comparison: MimicComparison.compare(reference: reference.take, attempt: attempt),
                localeIdentifier: session.transcriptionLocaleIdentifier
              )
            } else {
              practicePanel(session, reference: reference)
            }
          }
          .frame(maxWidth: 1050, alignment: .topLeading)
          .padding(.horizontal, 20)
          .padding(.vertical, 24)
          .frame(maxWidth: .infinity, alignment: .top)
        } else {
          ContentUnavailableView(
            "Reference unavailable", systemImage: "waveform.badge.exclamationmark",
            description: Text("This practice needs its reference audio.")
          )
          .frame(maxWidth: .infinity, minHeight: 350)
        }
      }
      transport
    }
  }

  private func heading(_ session: CoachingSession) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Text(PracticeCatalog.title(of: session))
          .font(.title3.weight(.semibold))
          .lineLimit(1)
          .truncationMode(.middle)
        Label("With reference", systemImage: "waveform.path")
          .font(.caption)
          .foregroundStyle(.secondary)
        if let locale = session.transcriptionLocaleIdentifier {
          Text(TranscriptionLanguagePreference.displayName(for: locale))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if !session.takes.isEmpty {
          if snapshot {
            Text(model.mimicWorkspaceMode.switchCase.title)
              .font(.caption.weight(.semibold))
              .padding(7)
              .background(Studio.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
          } else {
            if model.mimicWorkspaceMode != .practice {
              // Review has two views of the selected take; name both instead of hiding one.
              Picker(
                "Review view",
                selection: Binding(
                  get: { model.mimicWorkspaceMode },
                  set: { model.setMimicWorkspaceMode($0) }
                )
              ) {
                Text("Compare").tag(MimicWorkspaceMode.compare)
                Text("This take").tag(MimicWorkspaceMode.analysis)
              }
              .labelsHidden()
              .pickerStyle(.segmented)
              .frame(width: 170)
              .help("Compare with the reference, or see this take's own measurements")
              .disabled(model.isRecording || model.mimicPhase != .ready)
            }
            Picker(
              "View",
              selection: Binding(
                get: { model.mimicWorkspaceMode.switchCase },
                set: { model.setMimicWorkspaceMode($0) }
              )
            ) {
              ForEach(MimicWorkspaceMode.switchCases) { mode in
                Text(mode.title).tag(mode)
              }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)
            .disabled(model.isRecording || model.mimicPhase != .ready)
          }
        }
      }
      if !session.takes.isEmpty {
        TakeStrip(session: session)
      }
    }
  }

  private func referenceStrip(_ reference: MimicReference) -> some View {
    let audioAvailable =
      snapshot || FileManager.default.fileExists(atPath: reference.take.audioURL.path)
    return HStack(spacing: 12) {
      Button {
        model.toggleMimicPlayback()
      } label: {
        Image(
          systemName: model.isPlaying && model.mimicPlaybackSource == .reference
            ? "pause.fill" : "play.fill"
        )
        .frame(width: 30, height: 30)
      }
      .buttonStyle(.bordered)
      .help(model.isPlaying ? "Pause reference" : "Play reference")
      .disabled(
        !audioAvailable || model.isRecording || model.isAnalyzing || model.mimicPhase == .countIn(1)
          || model.mimicPhase == .countIn(2))

      VStack(alignment: .leading, spacing: 2) {
        SectionEyebrow(text: "Reference")
          .fixedSize()
        Text(reference.sourceName)
          .font(.callout.weight(.medium))
          .lineLimit(1)
      }
      Spacer()
      if !snapshot {
        Menu {
          Button(
            model.transcriptionEngine == .system
              ? "Re-transcribe in \(TranscriptionLanguagePreference.displayName(for: model.transcriptionLocale.identifier))"
              : "Re-transcribe with Parakeet"
          ) {
            model.retranscribeMimicReference()
          }
          SettingsLink { Text("Transcription Settings…") }
        } label: {
          Label("Transcript", systemImage: "text.bubble")
        }
        .disabled(!audioAvailable || !model.canRetranscribe)
      }
      Text(vcDuration(reference.take.result.metrics.duration))
        .font(.caption.monospacedDigit())
        .foregroundStyle(Studio.secondary)
    }
    .padding(14)
    .desktopPanel()
    .overlay(alignment: .bottomLeading) {
      if !audioAvailable {
        Text("Reference audio is missing. Earlier takes are still in Review.")
          .font(.caption)
          .foregroundStyle(.orange)
          .padding(.horizontal, 14)
          .padding(.bottom, 2)
      }
    }
  }

  private func practicePanel(_ session: CoachingSession, reference: MimicReference) -> some View {
    VStack(alignment: .leading, spacing: 24) {
      SectionEyebrow(text: model.isRecording ? "Recording" : "Practice")
      if let transcription = reference.take.transcription {
        MimicTranscriptText(
          transcription: transcription,
          activeIndex: (model.isPlaying || model.playbackTime > 0)
            && model.mimicPlaybackSource == .reference
            ? transcription.words.firstIndex(where: {
              model.playbackTime >= $0.start && model.playbackTime < $0.end
            }) : nil,
          activeColor: Studio.accent
        ) { _, word in model.seekMimic(source: .reference, to: word.start) }
        .font(.system(size: 28, weight: .medium))
        .lineSpacing(7)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
      } else {
        ContentUnavailableView(
          "No transcript", systemImage: "text.quote",
          description: Text(
            "You can still listen and record. Comparing words requires a transcript.")
        )
        .frame(maxWidth: .infinity, minHeight: 130)
      }

      Divider()

      if snapshot {
        HStack(spacing: 10) {
          ForEach(MimicStyle.allCases) { style in
            Text(style.title)
              .font(.caption)
              .padding(.horizontal, 12)
              .frame(height: 28)
              .background(
                session.mimicStyle == style ? Studio.accent.opacity(0.18) : Studio.surface,
                in: RoundedRectangle(cornerRadius: 6))
          }
        }
      } else {
        Picker(
          "Practice style",
          selection: Binding(
            get: { session.mimicStyle ?? .listenAndRepeat },
            set: { value in model.updateMimicStyle(value) }
          )
        ) {
          ForEach(MimicStyle.allCases) { style in
            Text(style.title).tag(style)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 360)
        .disabled(model.mimicPhase != .ready)
      }

      Text(
        session.mimicStyle == .speakAlong
          ? "Speak with the reference. Use headphones to keep it out of your recording."
          : "Listen to the reference, then record your version."
      )
      .font(.callout)
      .foregroundStyle(Studio.secondary)

      if model.isRecording {
        HStack(spacing: 12) {
          Button("Stop") { model.recordButtonPressed() }
            .tint(.red)
            .studioGlassButton(prominent: true)
            .controlSize(.large)
          Circle().fill(.red).frame(width: 9, height: 9)
          Text("Recording · \(vcDuration(model.elapsed))")
            .font(.headline.monospacedDigit())
          LiveMeterView(level: model.liveLevel)
            .frame(maxWidth: 260)
        }
      } else if case .countIn(let number) = model.mimicPhase {
        HStack(spacing: 12) {
          Button("Cancel") { model.cancelMimicCountIn() }
            .controlSize(.large)
          Text("Starting in \(number)…")
            .font(.headline.monospacedDigit())
        }
      } else if model.mimicPhase == .playingReference {
        HStack(spacing: 12) {
          Button("Cancel") { model.stopPlayback() }
            .keyboardShortcut(.space, modifiers: [])
            .controlSize(.large)
          Text("Listening… A 2-second count-in comes before recording.")
            .font(.callout)
            .foregroundStyle(Studio.secondary)
        }
      } else if model.isAnalyzing || model.mimicPhase == .analyzing {
        ProgressView("Analyzing…")
      } else {
        practiceActions
      }
      if model.hasPendingMimicWork {
        Divider()
        Text("This take isn’t saved yet.")
          .font(.callout)
        HStack {
          Button("Retry saving") { model.retryPendingMimicWork() }
          Button("Show in Finder") { model.revealPendingMimicAudio() }
        }
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .desktopPanel()
  }

  private var transport: some View {
    Group {
      if model.mimicWorkspaceMode == .compare, let session = model.selectedSession,
        let reference = session.mimicReference, let attempt = model.selectedTake
      {
        compareTransport(reference: reference.take, attempt: attempt)
      }
    }
  }

  private func compareTransport(reference: PracticeSession, attempt: PracticeSession) -> some View {
    let comparison = MimicComparison.compare(reference: reference, attempt: attempt)
    return VStack(spacing: 0) {
      MimicComparePlaybackRow(
        reference: reference,
        attempt: attempt,
        comparison: comparison
      )
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .frame(maxWidth: 1050)
      .frame(maxWidth: .infinity)
    }
    .transportBarBackground()
  }

  /// Listen and record sit right under the sentence they act on. Review lives in the
  /// Practice / Review switch, so there is no separate bottom bar in Practice.
  private var practiceActions: some View {
    HStack(spacing: 12) {
      Button {
        model.toggleMimicPlayback()
      } label: {
        Label("Listen", systemImage: "play.fill")
      }
      .keyboardShortcut(.space, modifiers: [])
      .controlSize(.large)
      .disabled(model.isAnalyzing || model.mimicPhase != .ready || model.hasPendingMimicWork)

      Button {
        model.startMimicPractice()
      } label: {
        Label("Record take", systemImage: "record.circle")
      }
      .studioGlassButton(prominent: true)
      .controlSize(.large)
      .help(
        model.selectedSession?.mimicStyle == .speakAlong
          ? "Play the reference while you record"
          : "Play the reference, then record")
      .disabled(
        model.isAnalyzing || model.isRequestingPermission || model.isPlaying
          || model.mimicPhase != .ready || model.hasPendingMimicWork)

      if model.selectedSession?.mimicStyle == .listenAndRepeat {
        Button("Record without listening") { model.startMimicPractice(skipReference: true) }
          .buttonStyle(.borderless)
          .font(.callout)
          .help("Start recording right away, without playing the reference first")
          .disabled(model.isAnalyzing || model.isPlaying || model.hasPendingMimicWork)
      }
    }
  }
}
