import Foundation

enum AppDestination: Equatable {
  case home
  case mimicStart
  case practice(UUID)
  case take(UUID, UUID)
  case library
  case mimics

  var navigationSection: NavigationSection {
    switch self {
    case .home, .mimicStart: .home
    case .practice: .mimics
    case .take: .library
    case .library: .library
    case .mimics: .mimics
    }
  }

  var isTake: Bool {
    if case .take = self { return true }
    return false
  }

  var isWorkspace: Bool {
    switch self {
    case .practice, .take: true
    default: false
    }
  }
}

enum NavigationSection: String, CaseIterable, Identifiable {
  case home = "Home"
  case library = "Library"
  case mimics = "Mimics"

  var id: Self { self }

  var title: String { rawValue }

  var symbol: String {
    switch self {
    case .home: "waveform"
    case .library: "rectangle.stack"
    case .mimics: "waveform.path"
    }
  }
}
