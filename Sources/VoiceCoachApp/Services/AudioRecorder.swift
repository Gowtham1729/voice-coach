import AVFoundation
import Foundation

@MainActor
protocol AudioRecording: AnyObject {
  var onPlaybackFinished: (() -> Void)? { get set }
  var onRecordingInterrupted: (() -> Void)? { get set }
  var currentTime: TimeInterval { get set }
  var playbackVolume: Float { get set }

  func start(url: URL) throws
  func stop()
  func peakLevel() -> Float
  func play(url: URL, from time: TimeInterval) throws
  func pausePlayback()
  func stopPlayback()
  func seek(to time: TimeInterval)
}

extension AudioRecording {
  func play(url: URL) throws {
    try play(url: url, from: 0)
  }
}

@MainActor
final class AudioRecorder: NSObject, AudioRecording, AVAudioRecorderDelegate, AVAudioPlayerDelegate
{
  private var recorder: AVAudioRecorder?
  private var player: AVAudioPlayer?
  var onPlaybackFinished: (() -> Void)?
  var onRecordingInterrupted: (() -> Void)?

  var currentTime: TimeInterval {
    get { player?.currentTime ?? 0 }
    set { player?.currentTime = newValue }
  }
  var playbackVolume: Float = 1 {
    didSet { player?.volume = playbackVolume }
  }

  func start(url: URL) throws {
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatLinearPCM),
      AVSampleRateKey: 48_000.0,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
    let recorder = try AVAudioRecorder(url: url, settings: settings)
    recorder.delegate = self
    recorder.isMeteringEnabled = true
    guard recorder.prepareToRecord(), recorder.record() else {
      throw RecorderError.couldNotStart
    }
    self.recorder = recorder
  }

  func stop() {
    recorder?.stop()
    recorder = nil
  }

  func peakLevel() -> Float {
    guard let recorder, recorder.isRecording else { return -80 }
    recorder.updateMeters()
    return recorder.peakPower(forChannel: 0)
  }

  func play(url: URL, from time: TimeInterval = 0) throws {
    if player == nil || player?.url != url {
      player = try AVAudioPlayer(contentsOf: url)
      player?.delegate = self
      player?.prepareToPlay()
    }
    guard let player else { throw RecorderError.couldNotPlay }
    player.volume = playbackVolume
    // Always position the player: a paused player for the same file is reused, and
    // would otherwise resume mid-clip when asked to play from the start.
    player.currentTime = max(0, min(time, player.duration > 0 ? player.duration : time))
    guard player.play() else { throw RecorderError.couldNotPlay }
  }

  func pausePlayback() {
    player?.pause()
  }

  func stopPlayback() {
    player?.stop()
    player = nil
  }

  func seek(to time: TimeInterval) {
    guard let player else { return }
    let target = max(0, min(time, player.duration))
    player.currentTime = target
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    playbackEnded(for: ObjectIdentifier(player))
  }

  nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    playbackEnded(for: ObjectIdentifier(player))
  }

  /// Ignores a finish callback from a player that has since been replaced, so a clip
  /// ending late cannot stop the one that started after it.
  private nonisolated func playbackEnded(for finished: ObjectIdentifier) {
    Task { @MainActor [weak self] in
      guard let self, let player = self.player, ObjectIdentifier(player) == finished else {
        return
      }
      self.onPlaybackFinished?()
    }
  }

  nonisolated func audioRecorderDidFinishRecording(
    _ recorder: AVAudioRecorder, successfully flag: Bool
  ) {
    Task { @MainActor [weak self] in
      guard let self, self.recorder === recorder else { return }
      self.recorder = nil
      self.onRecordingInterrupted?()
    }
  }

  nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
    Task { @MainActor [weak self] in
      guard let self, self.recorder === recorder else { return }
      self.recorder = nil
      self.onRecordingInterrupted?()
    }
  }
}

enum RecorderError: LocalizedError {
  case couldNotStart
  case microphoneDenied
  case couldNotPlay

  var errorDescription: String? {
    switch self {
    case .couldNotStart: "Check that a microphone is connected, then try again."
    case .couldNotPlay: "Try playing again, or record a new take."
    case .microphoneDenied:
      "Turn on Ichido in System Settings → Privacy & Security → Microphone."
    }
  }
}
