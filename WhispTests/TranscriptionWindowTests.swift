import XCTest
@testable import Whisp

final class TranscriptionWindowTests: XCTestCase {
    func testOverlapBelongsToOneWindow() {
        let absolute = TranscriptSegment(start: 299.8, end: 300.4, text: "граница", source: .geminiBackfill, model: "test")
        var relative = absolute
        relative.start -= 297
        relative.end -= 297
        let first = TranscriptionWindow.ownedSegments([absolute], start: 0, end: 300, duration: 600)
        let second = TranscriptionWindow.ownedSegments([relative], start: 300, end: 600, duration: 600)
        XCTAssertTrue(first.isEmpty)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].start, 299.8, accuracy: 0.001)
    }

    func testPhraseGroupingPreservesRepeatedWords() {
        let words = [
            TranscriptSegment(start: 0, end: 0.2, text: "Да", source: .geminiBackfill, model: "test"),
            TranscriptSegment(start: 0.3, end: 0.5, text: "да", source: .geminiBackfill, model: "test"),
            TranscriptSegment(start: 0.5, end: 0.6, text: ".", source: .geminiBackfill, model: "test")
        ]
        XCTAssertEqual(TranscriptionWindow.phrases(words).map(\.text), ["Да да."])
    }

    func testSpeakersAreScopedToTheirChunk() {
        let word = TranscriptSegment(start: 3, end: 4, text: "Привет", source: .geminiBackfill, model: "test", speaker: "spk_1")
        let a = TranscriptionWindow.ownedSegments([word], start: 0, end: 300, duration: 600)
        let b = TranscriptionWindow.ownedSegments([word], start: 300, end: 600, duration: 600)
        XCTAssertNotEqual(a.first?.speaker, b.first?.speaker)
    }
}
