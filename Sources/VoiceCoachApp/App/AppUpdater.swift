import Sparkle
import SwiftUI

@MainActor
final class AppUpdater: ObservableObject {
  private let controller = SPUStandardUpdaterController(
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }
}
