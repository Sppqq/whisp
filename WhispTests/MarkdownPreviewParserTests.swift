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
            MarkdownDisplayFormatting.readableFormula("$x \\to y$, $g \\approx 9{,}8$, $v_0^2 \\mp a \\cdot t^2$"),
            "x → y, g ≈ 9,8, v₀² ∓ a · t²"
        )
    }
}
