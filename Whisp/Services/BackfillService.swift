import Foundation
import UserNotifications

actor BackfillService {
    private let client: GeminiAPIClient
    private let model: String
    private let vocabulary: [String]
    private let processor: AudioPostProcessor

    init(client: GeminiAPIClient, model: String, vocabulary: [String], processor: AudioPostProcessor) {
        self.client = client
        self.model = model
        self.vocabulary = vocabulary
        self.processor = processor
    }

    func checkAvailability() async throws {
        try await client.probeTranscription(model)
    }

    func backfill(session: LectureSession, interval: FallbackInterval, mixURL: URL, directory: URL) async throws -> [TranscriptSegment] {
        guard let end = interval.end else { return [] }
        let slice = directory.appending(path: "backfill-\(interval.id.uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: slice) }
        try await processor.slice(source: mixURL, start: interval.start, end: end, destination: slice)
        let relative = try await client.transcribe(audioURL: slice, model: model, vocabulary: vocabulary)
        guard !relative.isEmpty else {
            throw GeminiAPIError(code: -1, status: "EMPTY", message: "Дорасшифровка не вернула речь; исходный текст сохранён", retryAfter: nil)
        }
        let offset = max(0, interval.start - 3)
        return TranscriptionWindow.phrases(relative.map { segment in
            var copy = segment
            copy.start += offset
            copy.end += offset
            copy.source = .geminiBackfill
            return copy
        }.filter { segment in
            let midpoint = (segment.start + segment.end) / 2
            return midpoint >= interval.start && midpoint < end
        })
    }

    func notifyAvailable(sessionTitle: String, providerName: String) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        let content = UNMutableNotificationContent()
        content.title = "\(providerName) снова доступен"
        content.body = "Можно дорасшифровать локальные участки лекции «\(sessionTitle)»."
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
