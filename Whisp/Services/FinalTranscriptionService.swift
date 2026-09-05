import AVFoundation
import Foundation

struct TranscriptionProgress: Sendable {
    let segments: [TranscriptSegment]
    let currentChunk: Int
    let totalChunks: Int
    let chunkStart: TimeInterval
    let chunkEnd: TimeInterval
    let totalDuration: TimeInterval
    let progress: Double
    let stageDescription: String
    let logMessage: String?
}

actor FinalTranscriptionService {
    typealias ProgressHandler = @Sendable (TranscriptionProgress) async -> Void

    private let client: GeminiAPIClient
    private let processor: AudioPostProcessor
    private let model: String
    private let vocabulary: [String]
    private let onProgress: ProgressHandler?

    init(
        client: GeminiAPIClient,
        processor: AudioPostProcessor,
        model: String,
        vocabulary: [String],
        onProgress: ProgressHandler? = nil
    ) {
        self.client = client
        self.processor = processor
        self.model = model
        self.vocabulary = vocabulary
        self.onProgress = onProgress
    }

    func transcribe(mixURL: URL, directory: URL) async throws -> [TranscriptSegment] {
        let asset = AVURLAsset(url: mixURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw AudioPostProcessor.ProcessingError.noAudio }
        let attributes = try mixURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let cacheKey = "v2|\(model)|\(mixURL.lastPathComponent)|\(attributes.fileSize ?? 0)|\(attributes.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(duration)"
        let chunkSize: TimeInterval = 300
        let totalChunks = max(1, Int(ceil(duration / chunkSize)))

        await onProgress?(TranscriptionProgress(
            segments: [],
            currentChunk: 0,
            totalChunks: totalChunks,
            chunkStart: 0,
            chunkEnd: 0,
            totalDuration: duration,
            progress: 0.02,
            stageDescription: "Подготовка к расшифровке (\(totalChunks) фрагментов по 5 мин)",
            logMessage: "Длительность аудио: \(WhispFormatting.timestamp(duration)) (\(WhispFormatting.durationDescription(duration))). Фрагментов: \(totalChunks)."
        ))

        var cursor: TimeInterval = 0
        var chunkIndex = 0
        var all: [TranscriptSegment] = []

        while cursor < duration {
            try Task.checkCancellation()
            let end = min(duration, cursor + chunkSize)
            let chunkNum = chunkIndex + 1
            let slice = directory.appending(path: String(format: "final-%06d.m4a", Int(cursor)))
            let checkpointURL = directory.appending(path: String(format: "transcript-%06d.json", Int(cursor)))
            defer { try? FileManager.default.removeItem(at: slice) }

            let baseFraction = Double(chunkIndex) / Double(totalChunks)
            let chunkFractionWeight = 1.0 / Double(totalChunks)

            let segments: [TranscriptSegment]
            if let data = try? Data(contentsOf: checkpointURL),
               let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data), checkpoint.key == cacheKey {
                segments = checkpoint.segments
                let currentTotalProgress = Double(chunkNum) / Double(totalChunks)
                await onProgress?(TranscriptionProgress(
                    segments: TranscriptionWindow.phrases(all + segments),
                    currentChunk: chunkNum,
                    totalChunks: totalChunks,
                    chunkStart: cursor,
                    chunkEnd: end,
                    totalDuration: duration,
                    progress: currentTotalProgress,
                    stageDescription: "Фрагмент \(chunkNum) из \(totalChunks): загружен из кэша",
                    logMessage: "Фрагмент \(chunkNum)/\(totalChunks) [\(WhispFormatting.timestamp(cursor)) – \(WhispFormatting.timestamp(end))] загружен из кэша (\(segments.count) сегментов)."
                ))
            } else {
                await onProgress?(TranscriptionProgress(
                    segments: TranscriptionWindow.phrases(all),
                    currentChunk: chunkNum,
                    totalChunks: totalChunks,
                    chunkStart: cursor,
                    chunkEnd: end,
                    totalDuration: duration,
                    progress: baseFraction + chunkFractionWeight * 0.1,
                    stageDescription: "Фрагмент \(chunkNum) из \(totalChunks): нарезка аудио (\(WhispFormatting.timestamp(cursor)) – \(WhispFormatting.timestamp(end)))",
                    logMessage: "Фрагмент \(chunkNum)/\(totalChunks): нарезка аудио [\(WhispFormatting.timestamp(cursor)) – \(WhispFormatting.timestamp(end))]..."
                ))
                try await processor.slice(source: mixURL, start: cursor, end: end, destination: slice)

                await onProgress?(TranscriptionProgress(
                    segments: TranscriptionWindow.phrases(all),
                    currentChunk: chunkNum,
                    totalChunks: totalChunks,
                    chunkStart: cursor,
                    chunkEnd: end,
                    totalDuration: duration,
                    progress: baseFraction + chunkFractionWeight * 0.3,
                    stageDescription: "Фрагмент \(chunkNum) из \(totalChunks): отправка в Gemini API...",
                    logMessage: "Фрагмент \(chunkNum)/\(totalChunks): отправка аудио в Gemini API..."
                ))

                let relative = try await client.transcribe(
                    audioURL: slice,
                    model: model,
                    vocabulary: vocabulary,
                    onStatus: { [weak self] status in
                        guard let self else { return }
                        Task {
                            await self.reportStatus(
                                status,
                                currentChunk: chunkNum,
                                totalChunks: totalChunks,
                                chunkStart: cursor,
                                chunkEnd: end,
                                totalDuration: duration,
                                baseFraction: baseFraction,
                                chunkFractionWeight: chunkFractionWeight,
                                currentSegments: TranscriptionWindow.phrases(all)
                            )
                        }
                    }
                )

                segments = TranscriptionWindow.ownedSegments(relative, start: cursor, end: end, duration: duration)
                try JSONEncoder().encode(Checkpoint(key: cacheKey, segments: segments)).write(to: checkpointURL, options: .atomic)

                let currentTotalProgress = Double(chunkNum) / Double(totalChunks)
                await onProgress?(TranscriptionProgress(
                    segments: TranscriptionWindow.phrases(all + segments),
                    currentChunk: chunkNum,
                    totalChunks: totalChunks,
                    chunkStart: cursor,
                    chunkEnd: end,
                    totalDuration: duration,
                    progress: currentTotalProgress,
                    stageDescription: "Фрагмент \(chunkNum) из \(totalChunks) готов",
                    logMessage: "Фрагмент \(chunkNum)/\(totalChunks): успешно расшифрован (\(segments.count) сегментов речи)."
                ))
            }

            all.append(contentsOf: segments)
            cursor = end
            chunkIndex += 1
            if cursor < duration { try await Task.sleep(for: .seconds(1)) }
        }

        guard !all.isEmpty else {
            throw GeminiAPIError(code: -1, status: "EMPTY", message: "В записи не найдена речь. Аудио сохранено.", retryAfter: nil)
        }
        return TranscriptionWindow.phrases(all)
    }

    private func reportStatus(
        _ status: String,
        currentChunk: Int,
        totalChunks: Int,
        chunkStart: TimeInterval,
        chunkEnd: TimeInterval,
        totalDuration: TimeInterval,
        baseFraction: Double,
        chunkFractionWeight: Double,
        currentSegments: [TranscriptSegment]
    ) async {
        let subProgress: Double
        if status.contains("Загрузка") {
            subProgress = 0.35
        } else if status.contains("Подготовка") {
            subProgress = 0.55
        } else if status.contains("Распознавание") {
            subProgress = 0.75
        } else {
            subProgress = 0.50
        }
        await onProgress?(TranscriptionProgress(
            segments: currentSegments,
            currentChunk: currentChunk,
            totalChunks: totalChunks,
            chunkStart: chunkStart,
            chunkEnd: chunkEnd,
            totalDuration: totalDuration,
            progress: baseFraction + chunkFractionWeight * subProgress,
            stageDescription: "Фрагмент \(currentChunk) из \(totalChunks): \(status)",
            logMessage: "Фрагмент \(currentChunk)/\(totalChunks): \(status)"
        ))
    }

    private struct Checkpoint: Codable {
        let key: String
        let segments: [TranscriptSegment]
    }
}
