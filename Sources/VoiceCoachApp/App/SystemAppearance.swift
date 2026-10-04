import AppKit
import SwiftUI

extension Notification.Name {
  /// Posted on the distributed center when System Settings changes Light/Dark.
  static let appleInterfaceThemeChanged = Notification.Name("AppleInterfaceThemeChangedNotification")
}

/// Keeps Ichido on the Mac system appearance.
///
/// `NSRequiresAquaSystemAppearance` in this app's preferences forces Aqua and
/// ignores later system changes. Drop it, then match the current system style.
@MainActor
final class SystemAppearance: ObservableObject {
  static let shared = SystemAppearance()

  @Published private(set) var colorScheme: ColorScheme

  private init() {
    colorScheme = Self.systemColorScheme()
    DistributedNotificationCenter.default().addObserver(
      forName: .appleInterfaceThemeChanged,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        SystemAppearance.shared.apply()
      }
    }
    NotificationCenter.default.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: NSWorkspace.shared,
      queue: .main
    ) { _ in
      Task { @MainActor in
        SystemAppearance.shared.apply()
      }
    }
  }

  func apply() {
    UserDefaults.standard.removeObject(forKey: "NSRequiresAquaSystemAppearance")
    let app = NSApplication.shared
    app.appearance = nil
    for window in app.windows {
      window.appearance = nil
    }
    let scheme = Self.systemColorScheme()
    if colorScheme != scheme {
      colorScheme = scheme
    }
  }

  private static func systemColorScheme() -> ColorScheme {
    // Read the native effective appearance after clearing overrides. The global
    // defaults domain can lag a theme notification and disagree with AppKit.
    NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? .dark : .light
  }

}

struct SystemAppearanceRoot<Content: View>: View {
  @ObservedObject private var appearance = SystemAppearance.shared
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .environment(\.colorScheme, appearance.colorScheme)
      .preferredColorScheme(appearance.colorScheme)
      .onAppear { appearance.apply() }
  }
}
