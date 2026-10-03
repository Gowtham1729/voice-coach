import AppKit
import SwiftUI

extension Notification.Name {
  /// Posted on the distributed center when System Settings changes Light/Dark.
  static let appleInterfaceThemeChanged = Notification.Name("AppleInterfaceThemeChangedNotification")
}

/// Keeps Voice Coach on the Mac system appearance.
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
    let scheme = Self.systemColorScheme()
    let app = NSApplication.shared
    app.appearance = nil
    for window in app.windows {
      window.appearance = nil
    }
    let effectiveDark = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    if effectiveDark != (scheme == .dark) {
      let appearance = NSAppearance(named: Self.appearanceName(for: scheme))
      app.appearance = appearance
      for window in app.windows {
        window.appearance = appearance
      }
    }
    if colorScheme != scheme {
      colorScheme = scheme
    }
  }

  private static func systemColorScheme() -> ColorScheme {
    let domain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
    let style = domain?["AppleInterfaceStyle"] as? String ?? ""
    return style.caseInsensitiveCompare("Dark") == .orderedSame ? .dark : .light
  }

  private static func appearanceName(for scheme: ColorScheme) -> NSAppearance.Name {
    let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    if scheme == .dark {
      return increaseContrast ? .accessibilityHighContrastDarkAqua : .darkAqua
    }
    return increaseContrast ? .accessibilityHighContrastAqua : .aqua
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
