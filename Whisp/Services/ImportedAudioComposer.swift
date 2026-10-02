import AVFoundation
import Foundation

enum ImportedAudioComposer {
    enum ComposerError: LocalizedError {
        case noAudio(URL)
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAudio(let url):
                "В файле «\(url.lastPathComponent)» не найдена аудиодорожка."
            case .exportFailed(let message):
                "Не удалось объединить аудиофайлы: \(message)"
            }
        }
    }

    static func concatenate(_ sources: [URL], destination: URL) async throws {
        guard !sources.isEmpty else { throw ComposerError.exportFailed("список файлов пуст") }
        guard sources.count > 1 else {
            if sources[0].standardizedFileURL != destination.standardizedFileURL {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: sources[0], to: destination)
            }
            return
        }

        let composition = AVMutableComposition()
        guard let outputTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ComposerError.exportFailed("не удалось создать аудиодорожку")
        }

        var insertAt = CMTime.zero
        for source in sources {
            let asset = AVURLAsset(url: source)
            guard let inputTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                throw ComposerError.noAudio(source)
            }
            let duration = try await asset.load(.duration)
            guard duration.seconds.isFinite, duration.seconds > 0 else { throw ComposerError.noAudio(source) }
            try outputTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: inputTrack,
                at: insertAt
            )
            insertAt = CMTimeAdd(insertAt, duration)
        }

        let temporary = destination.deletingLastPathComponent()
            .appending(path: "Объединение-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ComposerError.exportFailed("не удалось создать экспорт аудио")
        }
        exporter.outputURL = temporary
        exporter.outputFileType = .m4a
        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously { continuation.resume() }
        }
        guard exporter.status == .completed else {
            throw ComposerError.exportFailed(exporter.error?.localizedDescription ?? "экспорт отменён")
        }
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}
