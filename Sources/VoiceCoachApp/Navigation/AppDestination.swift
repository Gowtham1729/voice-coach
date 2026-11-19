import Foundation

/// What the detail column shows. `.home`, `.library` and `.mimics` all mean "nothing open":
/// the practice list stays beside the start panel, filtered by `AppModel.listFilter`.
enum AppDestination: Equatable {
  case home
  case mimicStart
  case practice(UUID)
  case take(UUID, UUID)
  case library
  case mimics

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
