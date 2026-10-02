import XCTest
@testable import Whisp

final class MarkdownPreviewParserTests: XCTestCase {
    func testFrontmatterIsHiddenAndObsidianBlocksBecomePreviewBlocks() {
        let markdown = """
        ---
        type: lecture
        subject: Физика
        ---
        # Кинематика

        > [!abstract] Связи в Obsidian
        > - Предмет: [[Физика]]
        > - Тема: [[Прямолинейное движение]]

        ![[Микрофон.m4a]]
        """

        XCTAssertEqual(
            MarkdownPreviewParser.parse(markdown),
            [
                .heading(level: 1, text: "Кинематика"),
                .callout(
                    title: "Связи в Obsidian",
                    body: "Предмет: [[Физика]]\nТема: [[Прямолинейное движение]]"
                ),
                .attachment("Микрофон.m4a")
            ]
        )
    }

    func testRepeatedParagraphsDoNotNeedUniqueContent() {
        let markdown = """
        Один абзац

        Один абзац
        """

        XCTAssertEqual(
            MarkdownPreviewParser.parse(markdown),
            [.paragraph("Один абзац"), .paragraph("Один абзац")]
        )
    }

    func testMarkdownTableBecomesStructuredPreviewBlock() {
        let markdown = """
        ### Формулы

        | № | Закон | По вертикали |
        | :-: | :--- | :--- |
        | 1 | $$v = v_0 \\pm a \\cdot t$$ | $$v = v_0 \\pm g \\cdot t$$ |
        | 2 | $$S = \\frac{a \\cdot t^2}{2}$$ | $$h = \\frac{g \\cdot t^2}{2}$$ |
        """

        XCTAssertEqual(
            MarkdownPreviewParser.parse(markdown),
            [
                .heading(level: 3, text: "Формулы"),
                .table(
                    headers: ["№", "Закон", "По вертикали"],
                    rows: [
                        ["1", "$$v = v_0 \\pm a \\cdot t$$", "$$v = v_0 \\pm g \\cdot t$$"],
                        ["2", "$$S = \\frac{a \\cdot t^2}{2}$$", "$$h = \\frac{g \\cdot t^2}{2}$$"]
                    ]
                )
            ]
        )
    }

    func testLatexCommandsBecomeReadableSymbols() {
        XCTAssertEqual(
            MarkdownDisplayFormatting.readableFormula("$x \\to y$, $g \\approx 9{,}8$, $v_0^2 \\mp a_y \\cdot t^2$"),
            "x → y, g ≈ 9,8, v₀² ∓ aᵧ · t²"
        )
    }

    func testImportantQuoteBecomesCallout() {
        XCTAssertEqual(
            MarkdownPreviewParser.parse("> **NB!** Формулу достаточно вывести из базового уравнения."),
            [.callout(title: "NB!", body: "Формулу достаточно вывести из базового уравнения.")]
        )
    }
    func testNumberedStepsRetainTheirOriginalNumbers() {
        XCTAssertEqual(MarkdownPreviewParser.parse("1. Первый шаг\n2. Второй шаг\n10) Последний шаг"), [
            .numbered("1. Первый шаг"), .numbered("2. Второй шаг"), .numbered("10) Последний шаг")
        ])
    }

    func testDisplayOmitsEmojiAndPreservesMathAndSource() {
        let source = "🔗 Связи: x² ≥ 2; Δv → 0; № 1 ✅"
        XCTAssertEqual(WhispFormatting.withoutDecorativeEmoji(source), "Связи: x² ≥ 2; Δv → 0; № 1")
        XCTAssertEqual(source, "🔗 Связи: x² ≥ 2; Δv → 0; № 1 ✅")
        XCTAssertEqual(String(MarkdownDisplayFormatting.attributed("🔗 **Связи**: $x \\geq 2$").characters), "Связи: x ≥ 2")
    }

}
