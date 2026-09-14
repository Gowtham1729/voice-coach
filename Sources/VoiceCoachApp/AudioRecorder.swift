import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    var onPlaybackFinished: (() -> Void)?

    var isRecording: Bool { recorder?.isRecording == true }

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

    func play(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
        guard player?.play() == true else { throw RecorderError.couldNotPlay }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
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
