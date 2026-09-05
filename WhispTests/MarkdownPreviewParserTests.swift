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
}
