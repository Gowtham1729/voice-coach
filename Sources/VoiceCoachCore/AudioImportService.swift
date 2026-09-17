import Foundation

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif

public enum AudioImportError: LocalizedError {
    case noAudioTrack
    case unsupportedMedia
    case exportFailed(String)
    case invalidExcerpt

    public var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            "This file does not contain an audio track to analyze."
        case .unsupportedMedia:
            "Choose an audio or video file that macOS can play."
        case .exportFailed(let detail):
            "Voice Coach could not prepare this clip. \(detail)"
        case .invalidExcerpt:
            "Choose an excerpt that is at least one second long and inside the clip."
        }
    }
}

public struct AudioImportService {
    #if canImport(UniformTypeIdentifiers)
    public static let allowedContentTypes: [UTType] = [.audio, .movie]
    #endif

    public static func source(for url: URL) -> TakeSource {
        let fileExtension = url.pathExtension.lowercased()
        switch fileExtension {
        case "3gp", "avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm":
            return .importedVideo
        default:
            break
        }
        #if canImport(UniformTypeIdentifiers)
        guard let type = UTType(filenameExtension: fileExtension) else { return .importedAudio }
        return type.conforms(to: .movie) ? .importedVideo : .importedAudio
        #else
        return .importedAudio
        #endif
    }

    public static func prepareAudio(from sourceURL: URL, to destinationURL: URL) async throws {
        #if canImport(AVFoundation)
        if source(for: sourceURL) == .importedAudio {
            try await normalizeAudio(from: sourceURL, to: destinationURL)
            return
        }

        let asset = AVURLAsset(url: sourceURL)
        guard try await asset.load(.isReadable) else {
            throw AudioImportError.unsupportedMedia
        }
        guard try await asset.loadTracks(withMediaType: .audio).isEmpty == false else {
            throw AudioImportError.noAudioTrack
        }
        guard await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPresetAppleM4A,
            with: asset,
            outputFileType: .m4a
        ), let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else { throw AudioImportError.unsupportedMedia }

        let exportedAudioURL = destinationURL.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: exportedAudioURL)
        defer { try? FileManager.default.removeItem(at: exportedAudioURL) }
        do {
            try await exporter.export(to: exportedAudioURL, as: .m4a)
            try await normalizeAudio(from: exportedAudioURL, to: destinationURL)
        } catch {
            let exportError = exporter.error ?? error
            let nsError = exportError as NSError
            let reason = nsError.localizedFailureReason ?? "Unknown media error."
            let detail = "\(nsError.localizedDescription) \(reason)"
            throw AudioImportError.exportFailed(detail)
        }
        #else
        throw AudioImportError.unsupportedMedia
        #endif
    }

    #if canImport(AVFoundation)
    public static func trimAudio(from sourceURL: URL, to destinationURL: URL, start: Double, end: Double) throws {
        let input = try AVAudioFile(forReading: sourceURL)
        let rate = input.processingFormat.sampleRate
        let first = AVAudioFramePosition((start * rate).rounded())
        let last = AVAudioFramePosition((end * rate).rounded())
        guard first >= 0, last <= input.length, last - first >= AVAudioFramePosition(rate),
              let chunk = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8_192),
              let excerpt = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8_192),
              let sourceChannels = chunk.floatChannelData,
              let destinationChannels = excerpt.floatChannelData
        else {
            throw AudioImportError.invalidExcerpt
        }
        let output = try AVAudioFile(
            forWriting: destinationURL,
            settings: input.processingFormat.settings,
            commonFormat: input.processingFormat.commonFormat,
            interleaved: input.processingFormat.isInterleaved
        )
        var cursor: AVAudioFramePosition = 0
        var written: AVAudioFramePosition = 0
        while cursor < last {
            try input.read(into: chunk, frameCount: chunk.frameCapacity)
            guard chunk.frameLength > 0 else { break }
            let from = max(0, first - cursor)
            let through = min(AVAudioFramePosition(chunk.frameLength), last - cursor)
            if through > from {
                let count = Int(through - from)
                excerpt.frameLength = AVAudioFrameCount(count)
                for channel in 0..<Int(input.processingFormat.channelCount) {
                    destinationChannels[channel].update(from: sourceChannels[channel].advanced(by: Int(from)), count: count)
                }
                try output.write(from: excerpt)
                written += AVAudioFramePosition(count)
            }
            cursor += AVAudioFramePosition(chunk.frameLength)
        }
        guard written == last - first else { throw AudioImportError.invalidExcerpt }
    }

    public static func waveform(from sourceURL: URL, buckets: Int = 0) throws -> (duration: Double, peaks: [Float]) {
        let input = try AVAudioFile(forReading: sourceURL)
        guard input.length > 0, buckets >= 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8_192)
        else { throw AudioImportError.unsupportedMedia }
        let duration = Double(input.length) / input.processingFormat.sampleRate
        let bucketCount = buckets == 0 ? min(24_000, max(300, Int(duration * 16))) : buckets
        var peaks = [Float](repeating: 0, count: bucketCount)
        while input.framePosition < input.length {
            let start = input.framePosition
            try input.read(into: buffer, frameCount: buffer.frameCapacity)
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { break }
            // Bucket a few samples per frame group; the curve is navigation, not analysis.
            for frame in stride(from: 0, to: Int(buffer.frameLength), by: 24) {
                let bucket = min(bucketCount - 1, Int(Double(start + AVAudioFramePosition(frame)) / Double(input.length) * Double(bucketCount)))
                for channel in 0..<Int(input.processingFormat.channelCount) {
                    peaks[bucket] = max(peaks[bucket], abs(channels[channel][frame]))
                }
            }
        }
        return (duration, peaks)
    }

    private static func normalizeAudio(from sourceURL: URL, to destinationURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let input = try AVAudioFile(forReading: sourceURL)
            let format = input.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_192) else {
                throw AudioImportError.unsupportedMedia
            }

            try? FileManager.default.removeItem(at: destinationURL)
            let output = try AVAudioFile(
                forWriting: destinationURL,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            while input.framePosition < input.length {
                try input.read(into: buffer, frameCount: buffer.frameCapacity)
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
            }
        }.value
    }
    #endif
}
