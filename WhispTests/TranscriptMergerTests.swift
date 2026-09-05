import XCTest
@testable import Whisp

final class TranscriptMergerTests: XCTestCase {
    func testEmptyBackfillCannotEraseExistingText() {
        let original = TranscriptSegment(start: 5, end: 9, text: "сохранить", source: .whisperFallback, model: "test")
        var interval = FallbackInterval(start: 5, reason: .network)
        interval.end = 9
        XCTAssertEqual(TranscriptMerger.applyBackfill(to: [original], interval: interval, replacements: []).map(\.text), ["сохранить"])
    }

    func testAdjacentAndDistantRepetitionsArePreserved() {
        let words = [0.0, 0.3, 10.0].map {
            TranscriptSegment(start: $0, end: $0 + 0.2, text: "да", source: .geminiBackfill, model: "test")
        }
        XCTAssertEqual(TranscriptMerger.merge(words).count, 3)
    }

    func testDifferentSpeakersAreNotDeduplicated() {
        let a = TranscriptSegment(start: 0, end: 1, text: "да", source: .geminiBackfill, model: "test", speaker: "a")
        var b = a
        b.speaker = "b"
        XCTAssertEqual(TranscriptMerger.merge([a, b]).count, 2)
    }

    func testGeminiReplacesOverlappingWhisper() {
        let local = TranscriptSegment(start: 10, end: 13, text: "модель оси", source: .whisperFallback, model: "whisper")
        let cloud = TranscriptSegment(start: 10.2, end: 13.1, text: "модель OSI", source: .geminiBackfill, model: "gemini")
        let merged = TranscriptMerger.merge([local, cloud])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].source, .geminiBackfill)
        XCTAssertEqual(merged[0].text, "модель OSI")
    }

    func testManualEditIsNeverOverwritten() {
        var edited = TranscriptSegment(start: 10, end: 13, text: "Модель OSI — ручная правка", source: .whisperFallback, model: "whisper")
        edited.manuallyEdited = true
        let cloud = TranscriptSegment(start: 10, end: 13, text: "модель оси", source: .geminiBackfill, model: "gemini")
        let merged = TranscriptMerger.merge([edited, cloud])
        XCTAssertEqual(merged.first?.text, edited.text)
    }

    func testBackfillOnlyTouchesInterval() {
        let before = TranscriptSegment(start: 0, end: 4, text: "Введение", source: .geminiLive, model: "live")
        let local = TranscriptSegment(start: 5, end: 9, text: "локальный текст", source: .whisperFallback, model: "whisper")
        let after = TranscriptSegment(start: 10, end: 14, text: "Итог", source: .geminiLive, model: "live")
        var interval = FallbackInterval(start: 5, reason: .quota)
        interval.end = 9
        let replacement = TranscriptSegment(start: 5, end: 9, text: "точный текст", source: .geminiBackfill, model: "gemini")
        let result = TranscriptMerger.applyBackfill(to: [before, local, after], interval: interval, replacements: [replacement])
        XCTAssertEqual(result.map(\.text), ["Введение", "точный текст", "Итог"])
    }
}
