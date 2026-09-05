import Foundation

enum TranscriptMerger {
    static func merge(_ segments: [TranscriptSegment], tolerance: TimeInterval = 0.6) -> [TranscriptSegment] {
        let sorted = segments.sorted { lhs, rhs in
            if lhs.start == rhs.start { return sourcePriority(lhs.source) > sourcePriority(rhs.source) }
            return lhs.start < rhs.start
        }
        var result: [TranscriptSegment] = []
        for segment in sorted where !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let index = result.lastIndex(where: { overlaps($0, segment, tolerance: tolerance) }) {
                if segment.manuallyEdited || sourcePriority(segment.source) >= sourcePriority(result[index].source) {
                    result[index] = preservingManualEdit(existing: result[index], replacement: segment)
                }
            } else {
                result.append(segment)
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    static func applyBackfill(
        to original: [TranscriptSegment],
        interval: FallbackInterval,
        replacements: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        guard let end = interval.end else { return original }
        let inside = replacements.filter {
            let midpoint = ($0.start + $0.end) / 2
            return midpoint >= interval.start && midpoint < end
        }
        guard !inside.isEmpty else { return original }
        let protected = original.filter { segment in
            segment.manuallyEdited || segment.end <= interval.start || segment.start >= end
        }
        return merge(protected + inside.map { replacement in
            var copy = replacement
            copy.source = .geminiBackfill
            return copy
        })
    }

    private static func overlaps(_ lhs: TranscriptSegment, _ rhs: TranscriptSegment, tolerance: TimeInterval) -> Bool {
        let temporal = lhs.start <= rhs.end + tolerance && rhs.start <= lhs.end + tolerance
        let textMatch = similarity(normalized(lhs.text), normalized(rhs.text)) >= 0.72
        let intersection = max(0, min(lhs.end, rhs.end) - max(lhs.start, rhs.start))
        let shorter = max(0.1, min(lhs.end - lhs.start, rhs.end - rhs.start))
        let sameAudioWindow = intersection / shorter >= 0.6 && lhs.source != rhs.source
        // Adjacent repetitions ("да, да") and different speakers are not duplicates.
        if let a = lhs.speaker, let b = rhs.speaker, a != b { return false }
        if lhs.source == rhs.source { return intersection > 0 && intersection / shorter >= 0.6 && textMatch }
        return temporal && (textMatch || sameAudioWindow)
    }

    private static func preservingManualEdit(existing: TranscriptSegment, replacement: TranscriptSegment) -> TranscriptSegment {
        existing.manuallyEdited ? existing : replacement
    }

    private static func sourcePriority(_ source: TranscriptSource) -> Int {
        switch source {
        case .whisperFallback: 0
        case .geminiLive: 1
        case .geminiBackfill: 2
        }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive], locale: .current)
            .components(separatedBy: .punctuationCharacters).joined()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs) { return 1 }
        let a = Set(lhs.split(separator: " "))
        let b = Set(rhs.split(separator: " "))
        return Double(a.intersection(b).count) / Double(max(1, a.union(b).count))
    }
}
