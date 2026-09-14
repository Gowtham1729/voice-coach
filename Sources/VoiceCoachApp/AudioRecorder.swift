import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    var onPlaybackFinished: (() -> Void)?

    var isRecording: Bool { recorder?.isRecording == true }
    var isPlaying: Bool { player?.isPlaying == true }
    var currentTime: TimeInterval {
        get { player?.currentTime ?? 0 }
        set { player?.currentTime = newValue }
    }
    var duration: TimeInterval { player?.duration ?? 0 }

    func start(url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 48_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
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
        if time > 0 {
            player.currentTime = min(time, player.duration > 0 ? player.duration : time)
        }
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
        Task { @MainActor [weak self] in self?.onPlaybackFinished?() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in self?.onPlaybackFinished?() }
    }
}

enum RecorderError: LocalizedError {
    case couldNotStart
    case microphoneDenied
    case couldNotPlay

    var errorDescription: String? {
        switch self {
        case .couldNotStart: "The recording could not start. Check that a microphone is connected."
        case .couldNotPlay: "The recording could not be played. Try recording another sample."
        case .microphoneDenied: "Microphone access is off. Enable Voice Coach in System Settings → Privacy & Security → Microphone."
        }
    }
}
