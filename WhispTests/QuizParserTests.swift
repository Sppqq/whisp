import XCTest
@testable import Whisp

final class QuizParserTests: XCTestCase {
    func testPitfallParagraphsAreGroupedAndMarkdownMarkersAreRemoved() {
        let markdown = """
        ## Опасные места на зачёте (типичные ошибки)
        **«Путь и перемещение — разные величины»**
        **Ошибка:**
        • Студент подставляет длину пути вместо проекции перемещения.
        **Как правильно:**
        • Использовать проекцию вектора перемещения.

        **«Знак ускорения при торможении»**
        **Ошибка:**
        • Знак выбирают без учёта направления оси.
        """

        let quiz = QuizParser.parse(markdown)

        XCTAssertEqual(quiz.pitfalls.count, 2)
        XCTAssertEqual(
            quiz.pitfalls[0],
            "«Путь и перемещение — разные величины»\nОшибка:\nСтудент подставляет длину пути вместо проекции перемещения.\nКак правильно:\nИспользовать проекцию вектора перемещения."
        )
        XCTAssertFalse(quiz.pitfalls.joined().contains("**"))
        XCTAssertFalse(quiz.pitfalls.joined().contains("•"))
    }

    func testPitfallFormulaIsReadableWithoutLatexCommands() {
        let markdown = """
        ## Опасные места на зачёте (типичные ошибки)
        **Знак ускорения**
        **Как правильно:**
        • Векторы \\vec{a} \\uparrow\\downarrow \\vec{v}, а изменение скорости равно $\\Delta v$.
        """

        let pitfall = QuizParser.parse(markdown).pitfalls[0]

        XCTAssertEqual(
            pitfall,
            "Знак ускорения\nКак правильно:\nВекторы a⃗ ↑↓ v⃗, а изменение скорости равно Δ v."
        )
        XCTAssertFalse(pitfall.contains("\\"))
        XCTAssertFalse(pitfall.contains("$"))
    }
}
