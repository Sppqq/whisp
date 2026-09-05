import Foundation

/// The wire format is shared by transcription and the availability probe.
enum GeminiTranscriptionPayload {
    static func request(model: String, audio: [String: Any]) -> [String: Any] {
        [
            "model": model,
            "store": false,
            "input": [audio],
            "generation_config": ["transcription_config": [
                "language_codes": ["ru-RU", "en-US"],
                // custom_vocabulary is incompatible with BOTH timestamps and diarization.
                // Keep vocabulary in Live only; do not add it here, even as an empty array.
                "mode": ["type": "verbatim", "diarization_mode": "speaker",
                         "timestamp_granularities": ["word"]]
            ]]
        ]
    }

    static func parse(_ data: Data, model: String) throws -> [TranscriptSegment] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw invalidResponse("Некорректный ответ расшифровки")
        }
        if let status = root["status"] as? String, status != "completed" {
            throw invalidResponse("Расшифровка не завершена: \(status)")
        }
        let steps = root["steps"] as? [[String: Any]] ?? []
        let content = steps.filter { ($0["type"] as? String) == "model_output" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
        let output = (root["outputs"] as? [[String: Any]]) ?? (root["output"] as? [[String: Any]]) ?? []
        let items = content.isEmpty ? output : content
        var segments: [TranscriptSegment] = []
        var lastValidEnd: Double = 0.0
        for item in items {
            let annotations = (item["annotations"] as? [[String: Any]] ?? [])
                .filter { ($0["type"] as? String) == "word_info" }
            if !annotations.isEmpty {
                for word in annotations {
                    guard let text = word["text"] as? String,
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let rawStart = seconds(word["start_offset"] ?? word["startOffset"])
                    let rawEnd = seconds(word["end_offset"] ?? word["endOffset"])
                    let start = rawStart ?? lastValidEnd
                    let end: Double
                    if let rawEnd, rawEnd >= start {
                        end = rawEnd
                    } else {
                        end = start + 0.25
                    }
                    lastValidEnd = end
                    segments.append(TranscriptSegment(
                        start: start,
                        end: end,
                        text: text,
                        source: .geminiBackfill,
                        model: model,
                        confidence: word["confidence"] as? Double,
                        speaker: word["speaker"] as? String
                    ))
                }
            } else if let text = item["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let start = seconds(item["start_time"] ?? item["startTime"]) ?? lastValidEnd
                let rawEnd = seconds(item["end_time"] ?? item["endTime"])
                let end = max(start, rawEnd ?? (start + 1.0))
                lastValidEnd = end
                segments.append(TranscriptSegment(
                    start: start,
                    end: end,
                    text: text,
                    source: .geminiBackfill,
                    model: model,
                    speaker: item["speaker"] as? String
                ))
            }
        }
        // SDK convenience text must never replace the detailed word annotations.
        if segments.isEmpty, let text = root["output_text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments = [TranscriptSegment(start: 0, end: 0, text: text, source: .geminiBackfill, model: model)]
        }
        guard !segments.isEmpty else {
            if items.contains(where: { ($0["type"] as? String) == "text" && ($0["text"] as? String) != nil }) {
                return [] // A valid silent chunk is not a malformed API response.
            }
            throw invalidResponse("Gemini не вернул распознанную речь. Аудио сохранено; можно повторить обработку.")
        }
        return segments.sorted { $0.start < $1.start }
    }

    static func seconds(_ value: Any?) -> Double? {
        let result: Double?
        if let number = value as? NSNumber {
            result = number.doubleValue
        } else if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            result = Double(trimmed.hasSuffix("s") ? String(trimmed.dropLast()) : trimmed)
        } else {
            result = nil
        }
        guard let result, result.isFinite, result >= 0 else { return nil }
        return result
    }

    private static func invalidResponse(_ message: String) -> GeminiAPIError {
        GeminiAPIError(code: -1, status: "TRANSCRIPTION", message: message, retryAfter: nil)
    }
}
