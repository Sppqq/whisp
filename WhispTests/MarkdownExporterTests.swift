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

    func testStoredNotesKeepObsidianPropertiesAndSkipMissingAudio() {
        var session = LectureSession()
        session.title = "Сохранённая лекция"
        session.subject = "Математика"
        session.captureSystemAudio = true
        session.studentNotesMarkdown = "## Единый конспект\n\nТекст без frontmatter."
        session.notesMarkdown = "## Кратко\n\nКраткое содержание."

        let bundle = MarkdownExporter.render(session: session, availableAudio: [])

        XCTAssertTrue(bundle.studentNotebook.hasPrefix("---\ntype: lecture"))
        XCTAssertTrue(bundle.studentNotebook.contains("subject: \"Математика\""))
        XCTAssertTrue(bundle.studentNotebook.contains("## Единый конспект"))
        XCTAssertTrue(bundle.studentNotebook.contains("audio: []"))
        XCTAssertFalse(bundle.studentNotebook.contains("![[Микрофон.m4a]]"))
        XCTAssertFalse(bundle.studentNotebook.contains("![[Системный звук.m4a]]"))
        XCTAssertTrue(bundle.notes.hasPrefix("---\ntype: transcript"))
        XCTAssertTrue(bundle.notes.contains("## Кратко"))
    }

    func testReviewStudentNotebookAddsNavigationAndAudioToPlainStoredText() {
        var session = LectureSession()
        session.title = "Физика"
        session.subject = "Физика"
        session.analysis = AnalysisResult(
            title: "Физика",
            subject: "Физика",
            confidence: 1,
            alternatives: [],
            summary: "",
            detailedNotes: "",
            studentNotebook: "",
            tags: ["кинематика"],
            keyConcepts: ["Ускорение"]
        )
        session.studentNotesMarkdown = "## Конспект\n\nТекст лекции."

        let preview = MarkdownExporter.reviewStudentNotebook(session: session)

        XCTAssertTrue(preview.contains("> [!abstract] 🔗 Связи в Obsidian"))
        XCTAssertTrue(preview.contains("**Ключевые понятия**: [[Ускорение]]"))
        XCTAssertTrue(preview.contains("**Теги**:"))
        XCTAssertTrue(preview.contains("![[Микрофон.m4a]]"))
        XCTAssertTrue(preview.contains("## Конспект"))
    }

    func testReviewStudentNotebookDoesNotDuplicateExistingNavigation() {
        var session = LectureSession()
        session.subject = "Химия"
        session.studentNotesMarkdown = """
        > [!abstract] 🔗 Связи в Obsidian
        > - **Предмет**: Химия

        ![[Микрофон.m4a]]

        Текст.
        """

        let preview = MarkdownExporter.reviewStudentNotebook(session: session)

        XCTAssertEqual(preview.components(separatedBy: "> [!abstract]").count - 1, 1)
        XCTAssertEqual(preview.components(separatedBy: "![[Микрофон.m4a]]").count - 1, 1)
    }

    func testRemindersAreIncludedInStoredAndPreviewNotes() {
        var session = LectureSession()
        session.title = "История"
        session.studentNotesMarkdown = "## Конспект\n\nТекст."
        session.notesMarkdown = "## Разбор\n\nТекст."
        session.analysis = AnalysisResult(
            title: "История",
            subject: "История",
            confidence: 1,
            alternatives: [],
            summary: "",
            detailedNotes: "",
            reminders: [ReminderDraft(title: "Принести карту", notes: "Подготовить карту Восточной Европы к следующему уроку.")]
        )

        let bundle = MarkdownExporter.render(session: session)
        let preview = MarkdownExporter.reviewStudentNotebook(session: session)

        for text in [bundle.studentNotebook, bundle.notes, preview] {
            XCTAssertTrue(text.contains("## ✅ Задания к следующему уроку"))
            XCTAssertTrue(text.contains("**Принести карту**"))
            XCTAssertTrue(text.contains("Подготовить карту Восточной Европы"))
        }
    }
}
