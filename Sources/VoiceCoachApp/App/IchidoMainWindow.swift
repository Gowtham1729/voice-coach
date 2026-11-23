import AppKit
import SwiftUI

/// Marks main windows so a menu bar action can reuse one, including a minimized window.
struct IchidoMainWindowMarker: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView { MarkerView() }
  func updateNSView(_ view: NSView, context: Context) {}

  private final class MarkerView: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      window?.identifier = IchidoMainWindow.identifier
    }
  }
}

@MainActor
enum IchidoMainWindow {
  static let sceneID = "ichido-main"
  static let identifier = NSUserInterfaceItemIdentifier(sceneID)

  static func show(openWindow: OpenWindowAction) {
    if let window = NSApp.windows.first(where: { $0.identifier == identifier }) {
      window.deminiaturize(nil)
      window.makeKeyAndOrderFront(nil)
    } else {
      openWindow(id: sceneID)
    }
    NSApp.activate(ignoringOtherApps: true)
  }
}
