import AppKit

@MainActor
final class VoiceCoachApplicationDelegate: NSObject, NSApplicationDelegate {
  weak var model: AppModel?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let model else { return .terminateNow }
    // A permission wait holds no audio, so it never asks and never blocks quitting.
    guard model.isPreparingAudio || model.hasUnsavedAudio else {
      model.discardInFlightWorkForQuit()
      return .terminateNow
    }
    sender.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    if model.hasUnsavedAudio {
      alert.messageText = "Quit and discard audio?"
      alert.informativeText = "The current recording or captured reference has not been saved."
    } else {
      alert.messageText = "Ichido is still preparing audio"
      alert.informativeText = "Quitting now stops it and discards the audio being prepared."
    }
    alert.addButton(withTitle: "Keep working")
    let quit = alert.addButton(withTitle: "Quit anyway")
    quit.hasDestructiveAction = true
    guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
    model.discardInFlightWorkForQuit()
    return .terminateNow
  }
}
