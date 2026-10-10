import AppKit

@MainActor
final class VoiceCoachApplicationDelegate: NSObject, NSApplicationDelegate {
  weak var model: AppModel?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let model else { return .terminateNow }
    if model.isAnalyzing || model.mimicIsPreparing || model.isRequestingPermission {
      sender.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = "Ichido is still preparing audio"
      alert.informativeText = "Wait for it to finish before quitting."
      alert.addButton(withTitle: "Keep Ichido open")
      alert.runModal()
      return .terminateCancel
    }
    guard model.isCapturingMimicReference || model.isRecording || model.hasMenuBarReference else {
      return .terminateNow
    }
    sender.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "Discard audio and quit?"
    alert.informativeText = "The current recording or captured reference has not been saved."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Keep Ichido open")
    alert.addButton(withTitle: "Discard and quit")
    guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
    model.cancelMimicPreparation()
    model.recorder.stop()
    model.timer?.invalidate()
    if let url = model.recordingURL { try? FileManager.default.removeItem(at: url) }
    model.discardPendingStandaloneIfEmpty()
    return .terminateNow
  }
}
