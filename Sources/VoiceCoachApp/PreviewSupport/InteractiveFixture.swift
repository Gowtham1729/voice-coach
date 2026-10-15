#if DEBUG
  import Foundation

  /// Opens an explicitly supplied fixture library for interactive Mac checks.
  /// Release builds always use the normal private library.
  @MainActor
  func interactiveFixtureModelIfRequested() -> AppModel? {
    guard let index = CommandLine.arguments.firstIndex(of: "--fixture-library"),
      CommandLine.arguments.indices.contains(index + 1)
    else { return nil }
    let root = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
    let model = AppModel(storageRoot: root)
    if let recording = model.sessions.first(where: { !$0.isMimic }),
      let take = recording.latestTake
    {
      model.openTake(sessionID: recording.id, takeID: take.id)
    }
    return model
  }
#endif
