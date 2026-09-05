import Foundation

struct GeminiAnalysisEnvelope: Decodable, Sendable {
    let title: String
    let subject: String
    let confidence: Double
    let alternatives: [String]
    let summary: String
    let detailedNotes: String
    let studentNotebook: String?
    let tags: [String]?
    let keyConcepts: [String]?
}
struct GeminiAPIError: Error, LocalizedError, Sendable {
    let code: Int
    let status: String
    let message: String
    let retryAfter: TimeInterval?

    var errorDescription: String? { message }

    var fallbackReason: FallbackReason {
        if code == 429 || status == "RESOURCE_EXHAUSTED" { return .quota }
        if code == 401 || code == 403 { return .authentication }
        if message.localizedCaseInsensitiveContains("location") { return .region }
        if message.localizedCaseInsensitiveContains("proxy") { return .proxy }
        if message.localizedCaseInsensitiveContains("timed out") { return .timeout }
        return .unknown
    }

    var isRateLimitOrQuota: Bool {
        if code == 429 || code == 503 || status == "RESOURCE_EXHAUSTED" || status == "UNAVAILABLE" { return true }
        let lower = message.lowercased()
        return lower.contains("quota exceeded") || lower.contains("rate limit") ||
               lower.contains("too many requests") || lower.contains("retry in") ||
               lower.contains("high demand") || lower.contains("overloaded") ||
               lower.contains("temporarily unavailable") || lower.contains("spikes in demand")
    }
}
