import Foundation
import WhisperKit

actor WhisperFallbackService {
    private let modelName: String
    private var whisper: WhisperKit?
    private var samples: [Float] = []
    private var bufferStartedAt: TimeInterval?
    private var lastVoiceAt: TimeInterval?
    private var isProcessing = false
    private let minimumSamples = 16_000
    private let maximumSamples = 16_000 * 25

    init(modelName: String = "large-v3-v20240930_626MB") {
        self.modelName = modelName
    }

    func prepare() async throws {
        guard whisper == nil else { return }
        whisper = try await WhisperKit(WhisperKitConfig(model: modelName))
    }

    func append(samples newSamples: [Float], at timestamp: TimeInterval) async -> TranscriptSegment? {
        guard !newSamples.isEmpty else { return nil }
        if bufferStartedAt == nil { bufferStartedAt = timestamp }
        samples.append(contentsOf: newSamples)

        let rms = sqrt(newSamples.reduce(0) { $0 + $1 * $1 } / Float(max(1, newSamples.count)))
        if rms > 0.012 { lastVoiceAt = timestamp }
        let silence = lastVoiceAt.map { timestamp - $0 > 0.9 } ?? false
        let forced = samples.count >= maximumSamples
        guard samples.count >= minimumSamples, (silence || forced), !isProcessing else { return nil }
        return await flush(endTime: timestamp)
    }

    func flush(endTime: TimeInterval) async -> TranscriptSegment? {
        guard !samples.isEmpty, !isProcessing else { return nil }
        isProcessing = true
        defer { isProcessing = false }
        let audio = samples
        let start = bufferStartedAt ?? max(0, endTime - Double(audio.count) / 16_000)
        samples.removeAll(keepingCapacity: true)
        bufferStartedAt = nil
        lastVoiceAt = nil
        do {
            try await prepare()
            let result = try await whisper?.transcribe(audioArray: audio)
            let text = result?.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(
                start: start,
                end: endTime,
                text: text,
                source: .whisperFallback,
                model: modelName
            )
        } catch {
            return nil
        }
    }
}
