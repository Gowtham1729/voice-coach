import AVFoundation
import CoreAudio
import Foundation

/// Captures Mac system output (not the microphone) via a Core Audio process tap.
///
/// Permission prompts on `AudioDeviceStart` when `NSAudioCaptureUsageDescription` is set.
/// Denied access often still returns `noErr` with silent buffers — callers should check `heardAudio`.
final class SystemAudioCapture: @unchecked Sendable {
    var onCaptureInterrupted: (() -> Void)?

    private let ioQueue = DispatchQueue(label: "com.gowtham.voicecoach.system-audio", qos: .userInteractive)
    private let state = CaptureState()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    /// Peak level in dBFS while capturing (same scale as `AVAudioRecorder`).
    func peakLevel() -> Float {
        let (active, peak) = state.read { ($0.isCapturing, $0.peakAbsolute) }
        guard active, peak > 1e-7 else { return -80 }
        return 20 * log10(peak)
    }

    /// True if any buffer rose above a near-silence floor during this capture.
    var heardAudio: Bool {
        state.read(\.sawNonSilentAudio)
    }

    func start(url: URL) throws {
        guard !state.read(\.isCapturing) else { throw SystemAudioCaptureError.alreadyCapturing }
        teardown(removing: nil)

        do {
            try activateCapture(writingTo: url)
        } catch {
            teardown(removing: url)
            throw error
        }

        state.write { $0.isCapturing = true }
    }

    func stop() {
        let wasActive = state.write { state -> Bool in
            let active = state.isCapturing
            state.isCapturing = false
            return active
        }
        guard wasActive else { return }
        teardown(removing: nil)
    }

    // MARK: - Setup

    private func activateCapture(writingTo url: URL) throws {
        let excludeIDs = (try? Self.processObjectID(for: getpid())).map { [$0] } ?? []
        let tapDescription = CATapDescription(monoGlobalTapButExcludeProcesses: excludeIDs)
        tapDescription.uuid = UUID()
        tapDescription.name = "Voice Coach System Audio"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted

        var createdTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &createdTap)
        guard tapStatus == noErr, createdTap != kAudioObjectUnknown else {
            throw SystemAudioCaptureError.setupFailed
        }
        tapID = createdTap

        var asbd = try Self.streamDescription(forTap: tapID)
        guard let tapFormat = AVAudioFormat(streamDescription: &asbd) else {
            throw SystemAudioCaptureError.setupFailed
        }

        let outputUID = try Self.defaultOutputDeviceUID()
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Voice Coach System Audio Aggregate",
            kAudioAggregateDeviceUIDKey: "com.gowtham.voicecoach.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        var createdAggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &createdAggregate
        )
        guard aggregateStatus == noErr, createdAggregate != kAudioObjectUnknown else {
            throw SystemAudioCaptureError.setupFailed
        }
        aggregateID = createdAggregate

        let fileFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: tapFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) ?? tapFormat

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: fileFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        state.write { state in
            state.audioFile = file
            state.writingFormat = fileFormat
            state.peakAbsolute = 0
            state.sawNonSilentAudio = false
            state.writeFailed = false
        }

        var createdProc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&createdProc, aggregateID, ioQueue) {
            [weak self] _, inInputData, _, _, _ in
            self?.handleIO(inputData: inInputData, tapFormat: tapFormat)
        }
        guard procStatus == noErr, let createdProc else {
            throw SystemAudioCaptureError.setupFailed
        }
        ioProcID = createdProc

        let startStatus = AudioDeviceStart(aggregateID, createdProc)
        guard startStatus == noErr else {
            throw SystemAudioCaptureError.setupFailed
        }
    }

    // MARK: - IO (runs on `ioQueue`)

    private func handleIO(inputData: UnsafePointer<AudioBufferList>?, tapFormat: AVAudioFormat) {
        guard let inputData else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: tapFormat, bufferListNoCopy: inputData, deallocator: nil),
              buffer.frameLength > 0 else { return }

        let (mono, localPeak) = Self.monoSamples(from: buffer, format: tapFormat)
        guard !mono.isEmpty else { return }

        let snapshot = state.write { state -> (AVAudioFile, AVAudioFormat)? in
            state.peakAbsolute = max(state.peakAbsolute, localPeak)
            if localPeak > 1e-4 { state.sawNonSilentAudio = true }
            guard state.isCapturing, !state.writeFailed,
                  let file = state.audioFile, let format = state.writingFormat else { return nil }
            return (file, format)
        }
        guard let (file, format) = snapshot else { return }

        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(mono.count)) else {
            return
        }
        out.frameLength = AVAudioFrameCount(mono.count)
        if let dest = out.floatChannelData?[0] {
            mono.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                dest.update(from: base, count: mono.count)
            }
        }

        do {
            try file.write(from: out)
        } catch {
            state.write { state in
                state.writeFailed = true
                state.isCapturing = false
            }
            DispatchQueue.main.async { [weak self] in
                self?.teardown(removing: nil)
                self?.onCaptureInterrupted?()
            }
        }
    }

    private static func monoSamples(from buffer: AVAudioPCMBuffer, format: AVAudioFormat) -> ([Float], Float) {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        guard channelCount > 0 else { return ([], 0) }

        var mono = [Float](repeating: 0, count: frameCount)
        var peak: Float = 0

        if format.isInterleaved, let interleaved = buffer.floatChannelData?[0] {
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    let sample = interleaved[frame * channelCount + channel]
                    sum += sample
                    peak = max(peak, abs(sample))
                }
                mono[frame] = sum / Float(channelCount)
            }
        } else if let channels = buffer.floatChannelData {
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    let sample = channels[channel][frame]
                    sum += sample
                    peak = max(peak, abs(sample))
                }
                mono[frame] = sum / Float(channelCount)
            }
        } else {
            return ([], 0)
        }

        return (mono, peak)
    }

    // MARK: - Teardown

    private func teardown(removing url: URL?) {
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }

        state.write { state in
            state.audioFile = nil
            state.writingFormat = nil
        }

        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Core Audio helpers

    private static func processObjectID(for pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pidValue = pid
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pidValue,
            &size,
            &objectID
        )
        guard status == noErr, objectID != kAudioObjectUnknown else {
            throw SystemAudioCaptureError.setupFailed
        }
        return objectID
    }

    private static func defaultOutputDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw SystemAudioCaptureError.setupFailed
        }

        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let uid else {
            throw SystemAudioCaptureError.setupFailed
        }
        return uid.takeRetainedValue() as String
    }

    private static func streamDescription(forTap tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr else { throw SystemAudioCaptureError.setupFailed }
        return asbd
    }
}

/// Lock-protected fields shared between the main thread and the audio IO queue.
private final class CaptureState: @unchecked Sendable {
    private let lock = NSLock()
    var audioFile: AVAudioFile?
    var writingFormat: AVAudioFormat?
    var isCapturing = false
    var peakAbsolute: Float = 0
    var sawNonSilentAudio = false
    var writeFailed = false

    func read<T>(_ body: (CaptureState) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(self)
    }

    func read<T>(_ keyPath: KeyPath<CaptureState, T>) -> T {
        read { $0[keyPath: keyPath] }
    }

    func write<T>(_ body: (CaptureState) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(self)
    }
}

enum SystemAudioCaptureError: LocalizedError {
    case alreadyCapturing
    case setupFailed
    case permissionOrSilent

    var errorDescription: String? {
        switch self {
        case .alreadyCapturing:
            "Mac audio capture is already running."
        case .setupFailed:
            "Voice Coach could not capture Mac audio. Check System Settings → Privacy & Security → Screen & System Audio Recording and allow Voice Coach (System Audio Recording Only is enough)."
        case .permissionOrSilent:
            "No Mac audio was captured. Play something on this Mac, then try again. If nothing was playing, grant Voice Coach access under System Settings → Privacy & Security → Screen & System Audio Recording."
        }
    }
}
