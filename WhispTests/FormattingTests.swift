import XCTest
@testable import Whisp

final class FormattingTests: XCTestCase {
    func testTimestamp() {
        XCTAssertEqual(WhispFormatting.timestamp(754.9), "12:34")
        XCTAssertEqual(WhispFormatting.timestamp(-1), "00:00")
    }

    func testSafePath() {
        XCTAssertEqual(WhispFormatting.safePathComponent("  Сети: TCP/IP?  "), "Сети TCP IP")
        XCTAssertEqual(WhispFormatting.safePathComponent("///"), "Без названия")
    }

    func testRussianFolderPath() throws {
        var session = LectureSession()
        session.startedAt = ISO8601DateFormatter().date(from: "2026-09-01T07:30:00Z")
        session.subject = "Информатика"
        session.title = "Модель OSI"
        XCTAssertEqual(
            WhispFormatting.lecturePath(for: session, root: "Учёба"),
            "Учёба/2026/Сентябрь/01/Информатика/Модель OSI"
        )
    }

    func testDatedTitle() {
        let date = ISO8601DateFormatter().date(from: "2026-09-02T12:00:00Z")!
        XCTAssertEqual(WhispFormatting.datedTitle(title: "Классификация веществ", date: date), "02.09.2026 — Классификация веществ")
        XCTAssertEqual(WhispFormatting.datedTitle(title: "02.09.2026 — Классификация веществ", date: date), "02.09.2026 — Классификация веществ")
        XCTAssertEqual(WhispFormatting.datedTitle(title: "Новая лекция", date: date), "02.09.2026 — Новая лекция")
        XCTAssertEqual(WhispFormatting.datedTitle(title: "", date: date), "02.09.2026 — Новая лекция")
    }

    func testFormatMarkdownNotes() {
        let input = "Повторение методов решения уравнений и систем## Основные ошибки в практической работе* Теория вероятностей:* Неправильное оформление задач: отсутствие \"Дано\", \"Найти\".* NB! На зачёте снимут балл.* Степени:* При возведении степени.1. Правило: a^m. 2. Пример: c^-6.\n#\n\n# # 1. Тема\n\n1.\n\n* *Способ подстановки:**"
        let formatted = WhispFormatting.formatMarkdownNotes(input)
        XCTAssertTrue(formatted.contains("систем\n\n## Основные ошибки"))
        XCTAssertTrue(formatted.contains("работе\n\n* Теория вероятностей:"))
        XCTAssertTrue(formatted.contains(".\n\n* NB!"))
        XCTAssertTrue(formatted.contains("балл.\n\n* Степени:"))
        XCTAssertTrue(formatted.contains("степени.\n\n1. Правило:"))
        XCTAssertTrue(formatted.contains("a^m.\n\n2. Пример:"))
        XCTAssertFalse(formatted.contains("\n#\n"))
        XCTAssertTrue(formatted.contains("## 1. Тема"))
        XCTAssertTrue(formatted.contains("1. **Способ подстановки:**"))
    }

    func testGluedTextAndHeadings() {
        let input = """
        # Общая биология[[Общая биология]] занимается:* [[Цитология]] (наука о клетке)
        ## Что такое жизнь?Определение [[Фридрих Энгельс|Ф. Энгельса]] (XIX век):Способ существования белковых тел
        белков."Однако, лектор отметил, что определение утратило актуальность.Контекст:
        ## Свойства живого1. **[[Единство химического состава]]*** Наличие 4-х элементов
        (или [[Биосистемы]]).***Важный момент:** Все биосистемы
        скепсис по поводу последнего.**Неясные места/Вопросы:*** Лектор упомянул
        """
        let formatted = WhispFormatting.formatMarkdownNotes(input)
        XCTAssertTrue(formatted.contains("# Общая биология\n\n[[Общая биология]]"))
        XCTAssertTrue(formatted.contains("занимается:\n\n* [[Цитология]]"))
        XCTAssertTrue(formatted.contains("## Что такое жизнь?\n\nОпределение"))
        XCTAssertTrue(formatted.contains("(XIX век):\n\nСпособ"))
        XCTAssertTrue(formatted.contains("белков.\" Однако"))
        XCTAssertTrue(formatted.contains("актуальность. Контекст:"))
        XCTAssertTrue(formatted.contains("## Свойства живого\n\n1. **[[Единство химического состава]]**\n\n* Наличие"))
        XCTAssertTrue(formatted.contains("(или [[Биосистемы]]).\n\n* **Важный момент:**"))
        XCTAssertTrue(formatted.contains("последнего.\n\n**Неясные места/Вопросы:**\n\n* Лектор"))
    }
}
