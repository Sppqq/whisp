import AVFoundation
import Foundation

@MainActor
final class MobileAudioCompressor {
    enum CompressionError: LocalizedError {
        case noAudio
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAudio: "В импортируемом файле не найден аудиопоток."
            case .exportFailed(let message): "Не удалось сжать аудио: \(message)"
            }
        }
    }

    /// Re-encodes imported audio as a speech-friendly AAC M4A. The source is
    /// never modified; only the app's local copy is replaced by the compact one.
    func compress(
        source: URL,
        destination: URL,
        onProgress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw CompressionError.noAudio
        }

        let temporary = destination.deletingLastPathComponent()
            .appending(path: "compressed-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CompressionError.exportFailed("экспортёр недоступен")
        }
        exporter.outputURL = temporary
        exporter.outputFileType = .m4a
        exporter.shouldOptimizeForNetworkUse = true
        _ = track // Loading the track above validates that the source is audio.

        onProgress?(0)
        let monitor = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { break }
                onProgress?(Double(exporter.progress))
                if exporter.status != .exporting { break }
            }
        }
        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }
        monitor.cancel()
        onProgress?(1)
        guard exporter.status == .completed else {
            throw CompressionError.exportFailed(exporter.error?.localizedDescription ?? "неизвестная ошибка")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        return destination
    }
}
