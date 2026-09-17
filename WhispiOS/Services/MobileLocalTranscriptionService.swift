import Foundation
import WhisperKit

/// Optional on-device fallback for iPhone. The model is downloaded by WhisperKit
/// only after the user enables the fallback setting and a remote request fails.
actor MobileLocalTranscriptionService {
    private let modelName: String
    private var whisper: WhisperKit?

    init(modelName: String = "small") {
        self.modelName = modelName
    }

    func transcribe(audioURL: URL) async throws -> [TranscriptSegment] {
        if whisper == nil {
            whisper = try await WhisperKit(WhisperKitConfig(model: modelName))
        }
        guard let whisper else { return [] }
        let results = try await whisper.transcribe(audioPath: audioURL.path)
        return results
            .flatMap(\.segments)
            .map { segment in
                TranscriptSegment(
                    start: TimeInterval(segment.start),
                    end: TimeInterval(segment.end),
                    text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    source: .whisperFallback,
                    model: modelName
                )
            }
            .filter { !$0.text.isEmpty }
    }
}
