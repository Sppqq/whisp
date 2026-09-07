import XCTest
@testable import Whisp

final class LibrarySearchIndexTests: XCTestCase {
    func testSearchCoversMetadataTranscriptAndGeneratedNotes() {
        var session = LectureSession()
        session.title = "Клеточная биология"
        session.subject = "Биология"
        session.finalTranscript = [
            TranscriptSegment(
                start: 0,
                end: 4,
                text: "Митохондрии вырабатывают энергию",
                source: .geminiBackfill,
                model: "test"
            )
        ]
        session.notesMarkdown = "## АТФ и клеточное дыхание"
        session.analysis = AnalysisResult(
            title: session.title,
            subject: session.subject,
            confidence: 0.9,
            alternatives: [],
            summary: "Обмен веществ",
            detailedNotes: "Подробный разбор",
            studentNotebook: "Краткий конспект",
            tags: ["клетка"],
            keyConcepts: ["Митохондрии"]
        )

        var index = LibrarySearchIndex()
        index.rebuild(sessions: [session])

        XCTAssertEqual(index.matchingIDs(for: "митохондрии"), Set([session.id]))
        XCTAssertEqual(index.matchingIDs(for: "клеточное дыхание"), Set([session.id]))
        XCTAssertEqual(index.matchingIDs(for: "биология"), Set([session.id]))
    }

    func testEmptyQueryReturnsEveryIndexedSession() {
        var first = LectureSession()
        first.title = "Первая лекция"
        var second = LectureSession()
        second.title = "Вторая лекция"

        var index = LibrarySearchIndex()
        index.rebuild(sessions: [first, second])

        XCTAssertEqual(index.matchingIDs(for: " "), Set([first.id, second.id]))
    }
}
