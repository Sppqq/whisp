import AVFoundation
import Foundation

actor AudioPostProcessor {
    enum ProcessingError: LocalizedError {
        case noAudio, exportFailed(String)
        var errorDescription: String? {
            switch self {
            case .noAudio: "Нет аудиосегментов"
            case .exportFailed(let message): "Не удалось собрать аудио: \(message)"
            }
        }
    }

    func finalize(session: LectureSession, directory: URL) async throws -> (microphone: URL, system: URL?, mix: URL) {
        let microphoneChunks = session.audioChunks.filter { $0.source == .microphone }
        guard !microphoneChunks.isEmpty else { throw ProcessingError.noAudio }
        let microphone = directory.appending(path: "Микрофон.m4a")
        try await concatenate(microphoneChunks, directory: directory, destination: microphone)

        var system: URL?
        let systemChunks = session.audioChunks.filter { $0.source == .system }
        if !systemChunks.isEmpty {
            let url = directory.appending(path: "Системный звук.m4a")
            try await concatenate(systemChunks, directory: directory, destination: url)
            system = url
        }

        let mix = directory.appending(path: "Обработка-микс.m4a")
        try await mixTracks(microphone: microphone, system: system, destination: mix)
        return (microphone, system, mix)
    }

    func prepareImportedAudio(source: URL, directory: URL) async throws -> URL {
        let destination = directory.appending(path: "Микрофон.m4a")
        if source.standardizedFileURL == destination.standardizedFileURL { return destination }
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }

        let ext = source.pathExtension.lowercased()

        // 1. If source is already an m4a, check if it's directly readable
        if ext == "m4a" {
            let asset = AVURLAsset(url: source)
            if let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty {
                try FileManager.default.copyItem(at: source, to: destination)
                return destination
            }
        }

        // 2. Try FFmpeg if available (handles all audio containers/codecs: MPEG-2 ADTS aac, wav, ogg, flac, etc.)
        if let ffmpeg = findFFmpeg() {
            if (try? await convertWithFFmpeg(ffmpegPath: ffmpeg, source: source, destination: destination)) != nil {
                let asset = AVURLAsset(url: destination)
                if let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty {
                    return destination
                }
            }
        }

        // 3. Fall back to AVAssetExportSession
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else {
            throw ProcessingError.noAudio
        }
        try await export(asset: asset, destination: destination)
        return destination
    }

    private func findFFmpeg() -> String? {
        let paths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
            "/bin/ffmpeg"
        ]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func convertWithFFmpeg(ffmpegPath: String, source: URL, destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            // First attempt quick copy remux (takes ~50ms for raw aac streams)
            let copyProcess = Process()
            copyProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
            copyProcess.arguments = ["-y", "-i", source.path, "-vn", "-c:a", "copy", destination.path]
            let copyPipe = Pipe()
            copyProcess.standardError = copyPipe
            copyProcess.standardOutput = copyPipe
            try copyProcess.run()
            copyProcess.waitUntilExit()

            if copyProcess.terminationStatus == 0,
               let size = try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64,
               size > 1024 {
                return
            }

            // Transcode to standard aac in m4a if stream copy is not sufficient
            let transcodeProcess = Process()
            transcodeProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
            transcodeProcess.arguments = ["-y", "-i", source.path, "-vn", "-c:a", "aac", "-b:a", "192k", destination.path]
            let transcodePipe = Pipe()
            transcodeProcess.standardError = transcodePipe
            transcodeProcess.standardOutput = transcodePipe
            try transcodeProcess.run()
            transcodeProcess.waitUntilExit()

            guard transcodeProcess.terminationStatus == 0 else {
                let data = transcodePipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                throw ProcessingError.exportFailed("FFmpeg error: \(output)")
            }
        }.value
    }

    func slice(source: URL, start: TimeInterval, end: TimeInterval, destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        guard start.isFinite, end.isFinite, duration.seconds.isFinite,
              start >= 0, end > start, start < duration.seconds else {
            throw ProcessingError.exportFailed("некорректный диапазон аудио")
        }
        let safeStart = max(0, start - 3)
        let safeEnd = min(duration.seconds, end + 3)
        try await export(
            asset: asset,
            destination: destination,
            timeRange: CMTimeRange(
                start: CMTime(seconds: safeStart, preferredTimescale: 600),
                duration: CMTime(seconds: safeEnd - safeStart, preferredTimescale: 600)
            )
        )
    }

    private func concatenate(_ chunks: [AudioChunk], directory: URL, destination: URL) async throws {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProcessingError.noAudio
        }
        var cursor = CMTime.zero
        for chunk in chunks.sorted(by: { $0.start < $1.start }) {
            let asset = AVURLAsset(url: directory.appending(path: chunk.relativePath))
            guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let duration = try await asset.load(.duration)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceTrack, at: cursor)
            cursor = cursor + duration
        }
        try await export(asset: composition, destination: destination)
    }

    private func mixTracks(microphone: URL, system: URL?, destination: URL) async throws {
        guard let system else {
            let asset = AVURLAsset(url: microphone)
            try await export(asset: asset, destination: destination)
            return
        }
        let composition = AVMutableComposition()
        var parameters: [AVMutableAudioMixInputParameters] = []
        for url in [microphone, system] {
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first,
                  let destinationTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let duration = try await asset.load(.duration)
            try destinationTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero)
            let input = AVMutableAudioMixInputParameters(track: destinationTrack)
            input.setVolume(0.65, at: .zero)
            parameters.append(input)
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        try await export(asset: composition, destination: destination, audioMix: audioMix)
    }

    private func export(asset: AVAsset, destination: URL, timeRange: CMTimeRange? = nil, audioMix: AVAudioMix? = nil) async throws {
        // Never destroy the previous playable file until its replacement is complete.
        let temporary = destination.deletingLastPathComponent().appending(path: "export-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ProcessingError.exportFailed("экспортёр недоступен")
        }
        exporter.outputURL = temporary
        exporter.outputFileType = .m4a
        if let timeRange { exporter.timeRange = timeRange }
        exporter.audioMix = audioMix
        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously { continuation.resume() }
        }
        guard exporter.status == .completed else {
            throw ProcessingError.exportFailed(exporter.error?.localizedDescription ?? "неизвестная ошибка")
        }
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}
