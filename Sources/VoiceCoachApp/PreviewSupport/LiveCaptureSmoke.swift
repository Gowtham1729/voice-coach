#if DEBUG
  import Foundation

  /// Opt-in device check. Use --test-library with an isolated folder
  /// and a generated speech WAV.
  @MainActor
  enum LiveCaptureSmoke {
    static func runIfRequested(model: AppModel) {
      guard let index = CommandLine.arguments.firstIndex(of: "--capture-smoke"),
        CommandLine.arguments.indices.contains(index + 1)
      else { return }
      let speechURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
      let reportURL = model.storageLocation.appendingPathComponent("capture-smoke.json")
      Task {
        var evidence: [String: Any] = [:]
        func report(_ phase: String) throws {
          evidence["phase"] = phase
          let data = try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
          try data.write(to: reportURL, options: .atomic)
        }
        do {
          try report("starting")
          let priorSessionIDs = Set(model.sessions.map(\.id))
          model.destination = .library
          try await startCapture(model: model)
          try report("playing-test-speech")
          try await play(speechURL)
          evidence["heardAudio"] = model.systemAudioCapture.heardAudio
          evidence["peakDBFS"] = Double(model.systemAudioCapture.peakLevel())
          evidence["elapsed"] = model.mimicReferenceCaptureElapsed
          model.reviewMenuBarReference()
          try report("preparing-reference")
          try await waitUntil { !model.mimicIsPreparing }
          guard let draft = model.mimicDraft else { throw SmokeError.noReferenceDraft }
          evidence["capturedDuration"] = draft.duration
          model.transcriptionEngine = .system
          model.transcriptionLocaleIdentifier = "en_US"
          model.createMimicSession(name: "Mac audio capture check", start: 0, end: min(8, draft.duration))
          try report("saving-reference")
          try await waitUntil { !model.mimicIsPreparing }
          guard let saved = model.sessions.first, saved.isMimic, !priorSessionIDs.contains(saved.id),
            try model.store.load().contains(where: { $0.id == saved.id })
          else { throw SmokeError.referenceNotSaved }
          evidence["savedSessionID"] = saved.id.uuidString
          evidence["savedDuration"] = saved.mimicReference?.take.result.metrics.duration
          evidence["transcribed"] = !(saved.mimicReference?.take.transcription?.text.isEmpty ?? true)
          if CommandLine.arguments.contains("--capture-smoke-auto-stop") {
            model.destination = .library
            try await startCapture(model: model)
            try report("checking-90-second-auto-stop")
            let deadline = ContinuousClock.now + .seconds(105)
            while model.isCapturingMimicReference {
              guard ContinuousClock.now < deadline else { throw SmokeError.timedOut }
              try await play(speechURL, volume: 0.05)
            }
            try await waitUntil { !model.mimicIsPreparing }
            guard let automaticDraft = model.mimicDraft,
              (89...91).contains(automaticDraft.duration), model.destination == .library,
              model.hasMenuBarReference
            else { throw SmokeError.automaticStopFailed }
            evidence["automaticStopDuration"] = automaticDraft.duration
            let stagedURL = automaticDraft.url
            model.discardMenuBarReference()
            guard !FileManager.default.fileExists(atPath: stagedURL.path),
              !model.hasMenuBarReference, model.canStartQuickPractice
            else { throw SmokeError.discardFailed }
            evidence["discardRemovedStagedAudio"] = true
          }
          if CommandLine.arguments.contains("--capture-smoke-self-playback") {
            try await startCapture(model: model)
            try report("checking-own-playback-exclusion")
            model.playMimicReference()
            guard model.isPlaying else { throw SmokeError.playbackFailed }
            try await waitUntil { !model.isPlaying }
            let ownPlaybackExcluded = !model.systemAudioCapture.heardAudio
            evidence["ownPlaybackExcluded"] = ownPlaybackExcluded
            model.reviewMenuBarReference()
            guard ownPlaybackExcluded,
              !model.hasMenuBarReference, model.mimicDraft == nil
            else { throw SmokeError.ownPlaybackWasCaptured }
            model.clearError()
          }
          try report("passed")
        } catch {
          evidence["error"] = model.errorMessage ?? String(describing: error)
          try? report("failed")
          model.cancelMimicPreparation()
        }
      }
    }

    private static func startCapture(model: AppModel) async throws {
      model.startMenuBarReferenceCapture()
      try await waitUntil { !model.isRequestingPermission }
      guard model.isCapturingMimicReference else { throw SmokeError.captureDidNotStart }
    }

    private static func play(_ url: URL, volume: Float = 1) async throws {
      try await Task.detached {
        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = ["-v", String(volume), url.path]
        try player.run()
        player.waitUntilExit()
        guard player.terminationStatus == 0 else { throw SmokeError.playbackFailed }
      }.value
    }

    private static func waitUntil(_ condition: () -> Bool) async throws {
      let deadline = ContinuousClock.now + .seconds(120)
      while !condition() {
        guard ContinuousClock.now < deadline else { throw SmokeError.timedOut }
        try await Task.sleep(for: .milliseconds(50))
      }
    }

    private enum SmokeError: Error {
      case captureDidNotStart, playbackFailed, noReferenceDraft, referenceNotSaved
      case automaticStopFailed, discardFailed, ownPlaybackWasCaptured, timedOut
    }
  }
#endif
