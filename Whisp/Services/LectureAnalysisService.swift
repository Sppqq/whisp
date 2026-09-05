import Foundation

actor LectureAnalysisService {
    private let client: GeminiAPIClient
    private let model: String

    init(client: GeminiAPIClient, model: String) {
        self.client = client
        self.model = model
    }

    func analyze(
        segments: [TranscriptSegment],
        subjects: [String],
        onStatus: (@Sendable (String) async -> Void)? = nil
    ) async throws -> AnalysisResult {
        let transcript = segments.sorted { $0.start < $1.start }.map {
            "[\(WhispFormatting.timestamp($0.start))] \($0.speaker.map { "\($0): " } ?? "")\($0.text)"
        }.joined(separator: "\n")
        let chunks = transcript.chunked(maxCharacters: 100_000)
        if chunks.count == 1 {
            await onStatus?("Создание конспекта через \(model)...")
            return try await client.analyze(transcript: transcript, subjects: subjects, model: model, onStatus: onStatus)
        }

        var extracts: [String] = []
        for (index, chunk) in chunks.enumerated() {
            await onStatus?("Анализ части \(index + 1) из \(chunks.count)...")
            let prompt = """
            Извлеки из части \(index + 1) лекции только содержащиеся в ней факты. Сохрани термины,
            определения, формулы, код, примеры, задания и неясные места. Верни подробный Markdown без домыслов.

            \(chunk)
            """
            extracts.append(try await client.generateText(prompt: prompt, model: model, onStatus: onStatus))
        }
        let combined = extracts.joined(separator: "\n\n---\n\n")
        if combined.count <= 120_000 {
            await onStatus?("Финализация конспекта...")
            return try await client.analyze(transcript: combined, subjects: subjects, model: model, onStatus: onStatus)
        }

        let reducedChunks = combined.chunked(maxCharacters: 100_000)
        var reductions: [String] = []
        for chunk in reducedChunks {
            reductions.append(try await client.generateText(
                prompt: "Сожми без потери фактов, терминов, формул, примеров и заданий. Не добавляй новое:\n\n\(chunk)",
                model: model,
                onStatus: onStatus
            ))
        }
        await onStatus?("Финализация конспекта...")
        return try await client.analyze(transcript: reductions.joined(separator: "\n\n"), subjects: subjects, model: model, onStatus: onStatus)
    }
}
private extension String {
    func chunked(maxCharacters: Int) -> [String] {
        guard count > maxCharacters else { return [self] }
        var chunks: [String] = []
        var current = ""
        for paragraph in components(separatedBy: "\n") {
            if current.count + paragraph.count + 1 > maxCharacters, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n") + paragraph
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
