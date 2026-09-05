import Foundation

enum TranscriptionWindow {
    /// A word in the three-second context belongs to exactly one main window.
    static func ownedSegments(_ segments: [TranscriptSegment], start: Double, end: Double, duration: Double) -> [TranscriptSegment] {
        let offset = max(0, start - 3)
        return segments.compactMap { segment in
            var copy = segment
            if segment.start == 0, segment.end == 0 {
                // Legacy/text-only response: retain it, but do not invent word timings.
                copy.start = start
                copy.end = end
            } else {
                copy.start += offset
                copy.end += offset
                let midpoint = (copy.start + copy.end) / 2
                guard midpoint >= start, midpoint < end else { return nil }
                copy.start = max(0, copy.start)
                copy.end = min(duration, copy.end)
            }
            // Speaker IDs are local to each API call, not identities across the lecture.
            if let speaker = copy.speaker { copy.speaker = "\(Int(start / 300) + 1):\(speaker)" }
            return copy
        }
    }

    static func phrases(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, last.speaker == segment.speaker,
               last.model == segment.model, last.source == segment.source,
               segment.start >= last.start, segment.start - last.end < 1.2,
               segment.end - last.start <= 15, last.text.count < 220,
               !last.manuallyEdited, !segment.manuallyEdited,
               last.text.last.map({ !".!?…".contains($0) }) == true {
                let index = result.count - 1
                let punctuation = segment.text.first.map { ",.!?;:…".contains($0) } ?? false
                result[index].text += (punctuation ? "" : " ") + segment.text
                result[index].end = max(last.end, segment.end)
            } else { result.append(segment) }
        }
        return result
    }
}
