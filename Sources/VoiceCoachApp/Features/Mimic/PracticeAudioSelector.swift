import SwiftUI
import VoiceCoachCore

struct PracticeAudioSelector: View {
  let draft: MimicReferenceDraft
  @Binding var editor: PracticeClipEditor
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var viewportStart = 0.0

  private var range: PracticeClipSelection { editor.activeSelection }
  private var viewportDuration: Double { min(30, draft.duration) }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      waveform
      if !editor.clips.isEmpty {
        HStack {
          Text("Suggested phrases").font(.subheadline.weight(.semibold))
          Text("\(editor.selectedIDs.count) of \(editor.clips.count) selected")
            .font(.caption).foregroundStyle(Studio.secondary)
          Spacer()
          if snapshot {
            Text("Custom clip").foregroundStyle(Studio.accent)
          } else {
            Button("Custom clip") {
              model.stopPlayback()
              editor.chooseCustomClip()
            }
            .buttonStyle(.borderless)
            .help("Choose your own range in the waveform.")
          }
        }
        phraseList
      }
    }
    .onChange(of: draft.id, initial: true) { _, _ in revealSelection() }
    .onChange(of: editor.activeID) { _, _ in revealSelection() }
  }

  private var waveform: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Text(editor.activeClip?.text ?? "Custom clip")
          .font(.callout.weight(.medium)).lineLimit(1)
          .help(editor.activeClip?.text ?? "Drag the handles to choose a clip.")
        Spacer()
        if editor.activeIsAdjusted {
          if snapshot {
            Text("Reset").foregroundStyle(Studio.accent)
          } else {
            Button("Reset") {
              model.stopPlayback()
              editor.resetActiveClip()
              revealSelection()
            }
            .buttonStyle(.borderless)
            .help("Restore this phrase’s suggested boundaries.")
          }
        }
      }
      MimicTrimWaveform(
        peaks: draft.peaks, duration: draft.duration,
        viewportStart: viewportStart, viewportDuration: viewportDuration,
        start: boundary(isStart: true), end: boundary(isStart: false),
        playbackTime: model.isPlaying ? model.playbackTime : nil
      )
      .frame(height: 82)
      if draft.duration > 30 {
        if snapshot {
          Capsule().fill(Studio.accent.opacity(0.3)).frame(height: 5)
        } else {
          Slider(value: $viewportStart, in: 0...(draft.duration - 30))
            .accessibilityLabel("Browse audio")
        }
      }
      HStack(spacing: 12) {
        Button(model.isPlaying ? "Stop" : "Play selection",
          systemImage: model.isPlaying ? "stop.fill" : "play.fill") {
          if model.isPlaying { model.stopPlayback() }
          else { model.playMimicDraft(start: range.start, end: range.end) }
        }
        .disabled(range.end - range.start < 1)
        .controlSize(.small)
        Spacer()
        Text("\(vcNumber(range.start, 1))–\(vcNumber(range.end, 1))s")
        Text("\(vcNumber(range.end - range.start, 1))s selected")
      }
      .font(.caption.monospacedDigit()).foregroundStyle(Studio.secondary)
    }
    .padding(16)
    .desktopPanel()
  }

  private var phraseList: some View {
    Group {
      if snapshot {
        VStack(spacing: 0) { rows }
      } else {
        ScrollViewReader { reader in
          ScrollView { VStack(spacing: 0) { rows } }
            .onChange(of: editor.activeID) { _, id in
              if let id {
                withAnimation(StudioMotion.quick(reduceMotion: reduceMotion)) {
                  reader.scrollTo(id, anchor: .center)
                }
              }
            }
        }
      }
    }
    .frame(height: min(195, CGFloat(editor.clips.count) * 65 - 1), alignment: .top)
    .clipped()
    .padding(8)
    .desktopPanel()
    .accessibilityLabel("Suggested phrases")
  }

  private var rows: some View {
    ForEach(editor.clips) { clip in
      HStack(spacing: 12) {
        if snapshot {
          Image(systemName: editor.selectedIDs.contains(clip.id) ? "checkmark.square.fill" : "square")
            .foregroundStyle(Studio.accent)
          phraseLabel(clip)
        } else {
          Toggle("Include phrase", isOn: Binding(
            get: { editor.selectedIDs.contains(clip.id) },
            set: { selected in
              model.stopPlayback()
              editor.setSelected(clip.id, selected: selected)
            }))
            .toggleStyle(.checkbox).labelsHidden()
            .accessibilityLabel("Include: \(clip.text)")
          Button {
            model.stopPlayback()
            editor.select(clip.id)
            revealSelection()
          } label: { phraseLabel(clip) }
          .buttonStyle(.plain)
          .accessibilityLabel("Adjust: \(clip.text)")
          .help("Select this phrase and adjust it in the waveform.")
        }
      }
      .frame(minHeight: 52)
      .padding(.horizontal, 12).padding(.vertical, 6)
      .background(editor.activeID == clip.id ? Studio.accent.opacity(0.1) : .clear,
        in: RoundedRectangle(cornerRadius: 8))
      .id(clip.id)
      if clip.id != editor.clips.last?.id { Divider().padding(.horizontal, 12) }
    }
  }

  private func phraseLabel(_ clip: SuggestedPracticeClip) -> some View {
    let selection = editor.selection(for: clip)
    return VStack(alignment: .leading, spacing: 4) {
      Text(clip.text).font(.callout).lineLimit(2).multilineTextAlignment(.leading)
      HStack(spacing: 8) {
        Text("\(vcNumber(selection.end - selection.start, 1))s")
        if selection.start != clip.start || selection.end != clip.end { Text("Adjusted") }
        Spacer()
        if editor.activeID == clip.id { Text("Editing").foregroundStyle(Studio.accent) }
      }
      .font(.caption).foregroundStyle(Studio.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  private func boundary(isStart: Bool) -> Binding<Double> {
    Binding(
      get: { isStart ? range.start : range.end },
      set: { value in
        model.stopPlayback()
        editor.setBoundary(value, isStart: isStart)
      })
  }

  private func revealSelection() {
    let middle = (range.start + range.end) / 2
    viewportStart = min(max(0, middle - viewportDuration / 2), max(0, draft.duration - viewportDuration))
  }
}
