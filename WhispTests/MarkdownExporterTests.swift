import XCTest
@testable import Whisp

final class MarkdownExporterTests: XCTestCase {
    func testFallbackStatusAndSourcesAreRendered() {
        var session = LectureSession()
        session.startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        session.title = "Тест"
        session.subject = "Физика"
        session.captureSystemAudio = true
        session.rawTranscript = [
            TranscriptSegment(start: 12, end: 15, text: "Локальная фраза", source: .whisperFallback, model: "whisper")
        ]
        var fallback = FallbackInterval(start: 10, reason: .quota)
        fallback.end = 20
        session.fallbackIntervals = [fallback]
        let bundle = MarkdownExporter.render(session: session)
        XCTAssertTrue(bundle.raw.contains("transcription_status: local_fallback"))
        XCTAssertTrue(bundle.raw.contains("локальная страховка"))
        XCTAssertTrue(bundle.studentNotebook.contains("![[Системный звук.m4a]]"))
        XCTAssertFalse(bundle.final.contains("![[Системный звук.m4a]]"))
        XCTAssertFalse(bundle.raw.contains("![[Микрофон.m4a]]"))
        XCTAssertTrue(bundle.studentNotebook.contains("subject: \"Физика\""))
        XCTAssertFalse(bundle.studentNotebook.contains("\\(escapeYAML"))
        XCTAssertTrue(bundle.studentNotebook.contains("tags:\n  - физика\n  - ноябрь"))
        XCTAssertFalse(bundle.studentNotebook.contains("лекция"))
        XCTAssertFalse(bundle.raw.contains("tags:"))
        XCTAssertFalse(bundle.final.contains("tags:"))
        XCTAssertTrue(bundle.notes.contains("# Тест — Разбор нейросетью"))
        XCTAssertFalse(bundle.notes.contains("tags:"))
    }
}
