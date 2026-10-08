import AVFoundation
import Foundation

/// Makes compact, speech-friendly copies of lecture audio for the cloud.
///
/// Local recordings keep their original quality for playback and
/// re-transcription; WebDAV receives mono AAC instead (about 20–25 MB per
/// hour instead of ~115 MB). Copies are cached next to the lecture and reused
/// until the source file changes.
actor CloudAudioCompressor {
    static let shared = CloudAudioCompressor()

    /// Hidden folder inside the lecture directory; never uploaded itself.
    static let cacheFolderName = ".cloud-audio"
    static let compressibleFileNames: Set<String> = ["Микрофон.m4a", "Системный звук.m4a"]

    enum CompressionError: LocalizedError {
        case noAudio
        case encodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAudio: "В файле нет аудиодорожки."
            case .encodingFailed(let message): "Не удалось сжать аудио: \(message)"
            }
        }
    }

    /// Encoder settings from most to least compact; the first one the system
    /// AAC encoder accepts is used.
    private static let profiles: [(sampleRate: Double, bitRate: Int)] = [
        (32_000, 48_000),
        (44_100, 48_000),
        (44_100, 64_000)
    ]

    /// Returns the file to upload: a compressed copy, or the original when it
    /// is already compact or compression fails.
    func cloudCopy(of source: URL, lectureDirectory: URL) async -> URL {
        do {
            return try await compressedCopy(of: source, lectureDirectory: lectureDirectory)
        } catch {
            return source
        }
    }

    func compressedCopy(of source: URL, lectureDirectory: URL) async throws -> URL {
        let fileManager = FileManager.default
        let cacheDirectory = lectureDirectory.appending(path: Self.cacheFolderName, directoryHint: .isDirectory)
        let destination = cacheDirectory.appending(path: source.lastPathComponent)
        let sourceAttributes = try fileManager.attributesOfItem(atPath: source.path)
        let sourceDate = sourceAttributes[.modificationDate] as? Date ?? .distantFuture
        let sourceSize = (sourceAttributes[.size] as? NSNumber)?.int64Value ?? 0

        if let cached = try? fileManager.attributesOfItem(atPath: destination.path),
           let cachedDate = cached[.modificationDate] as? Date,
           cachedDate >= sourceDate {
            return destination
        }

        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, sourceSize > 0 else { return source }
        // Already compact, for example audio restored from the cloud.
        let sourceBitRate = Double(sourceSize) * 8 / duration
        if sourceBitRate <= Double(Self.profiles[0].bitRate) * 1.3 { return source }

        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let temporary = cacheDirectory.appending(path: "encode-\(UUID().uuidString).m4a")
        defer { try? fileManager.removeItem(at: temporary) }
        try await encode(asset: asset, to: temporary)

        let compressedSize = ((try? fileManager.attributesOfItem(atPath: temporary.path))?[.size] as? NSNumber)?.int64Value ?? 0
        guard compressedSize > 0, compressedSize < sourceSize else { return source }
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        return destination
    }

    private func encode(asset: AVAsset, to destination: URL) async throws {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw CompressionError.noAudio
        }
        var lastError: Error = CompressionError.encodingFailed("кодировщик AAC недоступен")
        for profile in Self.profiles {
            try Task.checkCancellation()
            do {
                if try await encode(track: track, asset: asset, to: destination, sampleRate: profile.sampleRate, bitRate: profile.bitRate) {
                    return
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Returns false when the encoder does not support this profile.
    private func encode(track: AVAssetTrack, asset: AVAsset, to destination: URL, sampleRate: Double, bitRate: Int) async throws -> Bool {
        try? FileManager.default.removeItem(at: destination)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate
        ]
        let writer = try AVAssetWriter(outputURL: destination, fileType: .m4a)
        guard writer.canApply(outputSettings: outputSettings, forMediaType: .audio) else { return false }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        writer.shouldOptimizeForNetworkUse = true

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return false }
        reader.add(output)

        guard reader.startReading() else {
            throw CompressionError.encodingFailed(reader.error?.localizedDescription ?? "не удалось прочитать запись")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw CompressionError.encodingFailed(writer.error?.localizedDescription ?? "не удалось начать запись")
        }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "whisp.cloud-audio-compressor")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let buffer = output.copyNextSampleBuffer(), input.append(buffer) else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }

        if reader.status == .failed || writer.status == .failed {
            reader.cancelReading()
            writer.cancelWriting()
            throw CompressionError.encodingFailed((reader.error ?? writer.error)?.localizedDescription ?? "неизвестная ошибка")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw CompressionError.encodingFailed(writer.error?.localizedDescription ?? "неизвестная ошибка")
        }
        return true
    }
}
