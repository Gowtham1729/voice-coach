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
      errorMessage =
        "This recording could not be played. Its audio file may have been moved. \(error.localizedDescription)"
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
      } catch { errorMessage = error.localizedDescription }
    }
  }

  func exportCurrent() {
    guard let take = selectedTake else { return }
    let panel = NSOpenPanel()
    panel.title = "Choose where to export this Voice Coach take"
    panel.prompt = "Export Here"
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
      toastMessage = "Exported audio and report"
      NSWorkspace.shared.activateFileViewerSelecting([folder])
    } catch { errorMessage = "Could not export the take: \(error.localizedDescription)" }
  }

  func revealStorage() { NSWorkspace.shared.activateFileViewerSelecting([storageLocation]) }
}
