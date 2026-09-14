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

    public var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            "This file does not contain an audio track to analyze."
        case .unsupportedMedia:
            "Choose an audio or video file that macOS can play."
        case .exportFailed(let detail):
            "Voice Coach could not prepare this clip. \(detail)"
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
