import AppKit
import Foundation

extension AppModel {
  func playCurrent() {
    guard !isRecording, !isAnalyzing else { return }
    if isPlaying {
      pausePlayback()
      return
    }
    guard let take = selectedTake else { return }
    let duration = take.result.metrics.duration
    let startTime = playbackTime >= max(duration - 0.05, 0) ? 0 : playbackTime
    do {
      try recorder.play(url: take.audioURL, from: startTime)
      playbackTime = startTime
      isPlaying = true
      startPlaybackTimer()
    } catch {
      presentError(
        title: "Playback failed",
        message: "This recording’s audio file is missing or unreadable.")
    }
  }

  func pausePlayback() {
    recorder.pausePlayback()
    stopPlaybackTimer()
    isPlaying = false
  }

  func stopPlayback() {
    recorder.stopPlayback()
    stopPlaybackTimer()
    isPlaying = false
    playbackTime = 0
    mimicPlaybackEnd = nil
    if mimicPhase == .playingReference {
      mimicShouldRecordAfterPlayback = false
      mimicPhase = .ready
    }
  }

  func seek(to time: TimeInterval, autoplay: Bool = false) {
    guard let take = selectedTake, !isRecording, !isAnalyzing else { return }
    let clamped = max(0, min(time, take.result.metrics.duration))
    playbackTime = clamped
    if isPlaying {
      recorder.seek(to: clamped)
    } else if autoplay {
      do {
        try recorder.play(url: take.audioURL, from: clamped)
        isPlaying = true
        startPlaybackTimer()
      } catch {
        presentError(
          title: "Playback failed",
          message: "This recording’s audio file is missing or unreadable.")
      }
    }
  }

  func exportCurrent() {
    guard let take = selectedTake else { return }
    let panel = NSOpenPanel()
    panel.title = "Export Recording"
    panel.prompt = "Export"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let parent = panel.url else { return }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    let folder = parent.appendingPathComponent(
      "Voice Coach \(formatter.string(from: take.createdAt))", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
      let extensionName = take.audioURL.pathExtension.isEmpty ? "m4a" : take.audioURL.pathExtension
      try FileManager.default.copyItem(
        at: take.audioURL, to: folder.appendingPathComponent("recording.\(extensionName)"))
      try report.write(
        to: folder.appendingPathComponent("voice-report.json"), atomically: true, encoding: .utf8)
      toastMessage = "Export complete"
      NSWorkspace.shared.activateFileViewerSelecting([folder])
    } catch {
      presentError(title: "Export failed", message: "Couldn’t write the audio and report files.")
    }
  }

  func revealStorage() { NSWorkspace.shared.activateFileViewerSelecting([storageLocation]) }
}
