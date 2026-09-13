import SwiftUI

struct MarkdownPreview: View {
    let markdown: String

    private var blocks: [MarkdownPreviewBlock] {
        MarkdownPreviewParser.parse(markdown)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if blocks.isEmpty {
                    ContentUnavailableView(
                        "Здесь пока нет текста",
                        systemImage: "doc.text",
                        description: Text("Переключитесь в режим «Правка», чтобы добавить содержимое.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        MarkdownPreviewBlockView(block: block)
                    }
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(WhispPalette.content)
        .textSelection(.enabled)
    }
}

enum MarkdownPreviewBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(String)
    case quote(String)
    case callout(title: String, body: String)
    case attachment(String)
    case table(headers: [String], rows: [[String]])
    case divider

}

enum MarkdownPreviewParser {
    static func parse(_ markdown: String) -> [MarkdownPreviewBlock] {
        let lines = visibleLines(markdown)
        var blocks: [MarkdownPreviewBlock] = []
        var paragraph: [String] = []
        var index = 0

        func finishParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph = []
        }

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                finishParagraph()
                index += 1
                continue
            }

            if let heading = heading(from: line) {
                finishParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
            } else if line == "---" || line == "***" {
                finishParagraph()
                blocks.append(.divider)
            } else if line.hasPrefix("> [!") {
                finishParagraph()
                var quoted = [line]
                var next = index + 1
                while next < lines.count, lines[next].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quoted.append(lines[next].trimmingCharacters(in: .whitespaces))
                    next += 1
                }
                let parsed = callout(from: quoted)
                blocks.append(.callout(title: parsed.title, body: parsed.body))
                index = next - 1
            } else if let important = importantQuote(from: line) {
                finishParagraph()
                blocks.append(.callout(title: important.title, body: important.body))
            } else if line.hasPrefix(">") {
                finishParagraph()
                blocks.append(.quote(stripQuote(line)))
            } else if let attachment = attachmentName(from: line) {
                finishParagraph()
                blocks.append(.attachment(attachment))
            } else if let table = table(from: lines, startingAt: index) {
                finishParagraph()
                blocks.append(.table(headers: table.headers, rows: table.rows))
                index = table.endIndex
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                finishParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if let numbered = numberedItem(from: line) {
                finishParagraph()
                blocks.append(.numbered(numbered))
            } else {
                paragraph.append(line)
            }
            index += 1
        }

        finishParagraph()
        return blocks
    }

    private static func visibleLines(_ markdown: String) -> [String] {
        var lines = markdown.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return lines }
        if let closingIndex = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines.removeSubrange(0...closingIndex)
        }
        return lines
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func numberedItem(from line: String) -> String? {
        guard let range = line.range(of: "^[0-9]+[.)]\\s+", options: .regularExpression) else { return nil }
        return String(line[range.upperBound...])
    }

    private static func stripQuote(_ line: String) -> String {
        line.drop(while: { $0 == ">" || $0 == " " }).description
    }

    private static func callout(from lines: [String]) -> (title: String, body: String) {
        let first = lines.first ?? ""
        let markerEnd = first.firstIndex(of: "]")
        let rawTitle = markerEnd.map { String(first[first.index(after: $0)...]) } ?? ""
        let title = rawTitle.trimmingCharacters(in: .whitespaces)
        let body = lines.dropFirst()
            .map(stripQuote)
            .map { $0.replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return (title.isEmpty ? "Заметка" : title, body)
    }

    private static func importantQuote(from line: String) -> (title: String, body: String)? {
        guard let match = line.range(
            of: "^>\\s*\\*\\*([^*]+)\\*\\*\\s*(.*)$",
            options: .regularExpression
        ) else { return nil }
        let content = String(line[match])
            .replacingOccurrences(of: "^>\\s*", with: "", options: .regularExpression)
        guard let titleEnd = content.range(of: "**", options: [], range: content.index(content.startIndex, offsetBy: 2)..<content.endIndex) else {
            return nil
        }
        let title = String(content[content.index(content.startIndex, offsetBy: 2)..<titleEnd.lowerBound])
        let body = String(content[titleEnd.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (title, body)
    }

    private static func attachmentName(from line: String) -> String? {
        guard line.hasPrefix("![["), line.hasSuffix("]]"), line.count > 5 else { return nil }
        return String(line.dropFirst(3).dropLast(2))
    }

    private static func table(
        from lines: [String],
        startingAt index: Int
    ) -> (headers: [String], rows: [[String]], endIndex: Int)? {
        guard index + 1 < lines.count,
              let headers = tableCells(from: lines[index]),
              let separator = tableCells(from: lines[index + 1]),
              headers.count > 1,
              separator.count == headers.count,
              separator.allSatisfy({ $0.range(of: "^:?-+:?$", options: .regularExpression) != nil }) else {
            return nil
        }

        var rows: [[String]] = []
        var cursor = index + 2
        while cursor < lines.count, let cells = tableCells(from: lines[cursor]) {
            guard cells.count == headers.count else { break }
            rows.append(cells)
            cursor += 1
        }
        return (headers, rows, cursor - 1)
    }

    private static func tableCells(from line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return nil }
        return trimmed.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
    }
}

private struct MarkdownPreviewBlockView: View {
    let block: MarkdownPreviewBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownDisplayFormatting.attributed(text))
                .font(headingFont(level))
                .tracking(level == 1 ? -0.5 : 0)
                .padding(.top, level == 1 ? 6 : 10)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph(let text):
            Text(MarkdownDisplayFormatting.attributed(text))
                .font(.body)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(WhispPalette.accent).frame(width: 5, height: 5)
                Text(MarkdownDisplayFormatting.attributed(text))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 6)
        case .numbered(let text):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(WhispPalette.accent)
                Text(MarkdownDisplayFormatting.attributed(text))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)
        case .quote(let text):
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(WhispPalette.accent.opacity(0.7)).frame(width: 3)
                Text(MarkdownDisplayFormatting.attributed(text))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        case .callout(let title, let body):
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: "link")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhispPalette.accent)
                if !body.isEmpty {
                    Text(MarkdownDisplayFormatting.attributed(body))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .whispQuietSurface(cornerRadius: WhispMetrics.controlCornerRadius)
        case .attachment(let name):
            Label(MarkdownDisplayFormatting.cleanWikiText(name), systemImage: "paperclip")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)
        case .table(let headers, let rows):
            MarkdownPreviewTable(headers: headers, rows: rows)
        case .divider:
            Divider().opacity(0.55).padding(.vertical, 4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.bold)
        case 2: .title3.weight(.semibold)
        default: .headline
        }
    }
}

private struct MarkdownPreviewTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                tableRow(headers, isHeader: true)
                Divider().opacity(0.65)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    tableRow(row, isHeader: false)
                    if index < rows.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
            .padding(.horizontal, 4)
            .frame(minWidth: 700, alignment: .leading)
            .whispQuietSurface(cornerRadius: WhispMetrics.controlCornerRadius)
        }
    }

    private func tableRow(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(MarkdownDisplayFormatting.attributed(cell))
                    .font(isHeader ? .callout.weight(.semibold) : .callout)
                    .lineSpacing(3)
                    .frame(width: columnWidth(at: index), alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, isHeader ? 10 : 9)

                if index < cells.count - 1 {
                    Divider().opacity(0.4)
                }
            }
        }
    }

    private func columnWidth(at index: Int) -> CGFloat {
        if index == 0, headers[index].count <= 3 { return 38 }
        return headers.count <= 3 ? 290 : 210
    }
}

enum MarkdownDisplayFormatting {
    static func attributed(_ source: String) -> AttributedString {
        let cleaned = readableFormula(cleanWikiText(source))
        return (try? AttributedString(
            markdown: cleaned,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(cleaned)
    }

    static func cleanWikiText(_ source: String) -> String {
        source
            .replacingOccurrences(
                of: "!?\\[\\[([^\\]|]+)\\|([^\\]]+)\\]\\]",
                with: "$2",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "!?\\[\\[([^\\]]+)\\]\\]",
                with: "$1",
                options: .regularExpression
            )
    }

    static func readableFormula(_ source: String) -> String {
        var value = source
        let patterns = [
            ("\\\\vec\\{([^{}]+)\\}", "$1⃗"),
            ("\\\\frac\\{([^{}]+)\\}\\{([^{}]+)\\}", "($1)/($2)"),
            ("\\\\sqrt\\{([^{}]+)\\}", "√($1)"),
            ("\\\\(?:mathrm|text)\\{([^{}]+)\\}", "$1")
        ]
        for (pattern, replacement) in patterns {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        let symbols = [
            ("\\uparrow", "↑"), ("\\downarrow", "↓"), ("\\rightarrow", "→"),
            ("\\leftarrow", "←"), ("\\to", "→"), ("\\cdot", "·"), ("\\times", "×"),
            ("\\Delta", "Δ"), ("\\leq", "≤"), ("\\geq", "≥"), ("\\neq", "≠"),
            ("\\approx", "≈"), ("\\implies", "⇒"), ("\\pm", "±"), ("\\mp", "∓"),
            ("\\alpha", "α"), ("\\beta", "β"), ("\\eta", "η"),
            ("\\sin", "sin"), ("\\cos", "cos"), ("\\left", ""), ("\\right", ""),
            ("\\%", "%"), ("\\/", "/"), ("{,}", ","), ("\\;", " "), ("\\,", " ")
        ]
        for (source, replacement) in symbols {
            value = value.replacingOccurrences(of: source, with: replacement)
        }
        value = readableSubscripts(value)
        value = value
            .replacingOccurrences(of: "^2", with: "²")
            .replacingOccurrences(of: "^3", with: "³")

        return value
            .replacingOccurrences(of: "\\(", with: "")
            .replacingOccurrences(of: "\\)", with: "")
            .replacingOccurrences(of: "$", with: "")
    }

    private static func readableSubscripts(_ source: String) -> String {
        let braced = source.replacingOccurrences(
            of: "_\\{([^{}]+)\\}",
            with: "_$1",
            options: .regularExpression
        )
        let expression = try? NSRegularExpression(pattern: "_([A-Za-zА-Яа-я0-9]+)")
        guard let expression else { return braced }
        var result = braced
        let matches = expression.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
        for match in matches {
            guard let range = Range(match.range(at: 1), in: result) else { continue }
            let raw = String(result[range])
            let converted = subscriptText(raw)
            let fullRange = Range(match.range(at: 0), in: result)!
            result.replaceSubrange(fullRange, with: converted)
        }
        return result
    }

    private static func subscriptText(_ source: String) -> String {
        let symbols: [Character: Character] = [
            "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
            "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
            "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ",
            "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ",
            "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ",
            "v": "ᵥ", "x": "ₓ", "y": "ᵧ"
        ]
        let converted = source.map { symbols[$0] ?? $0 }
        if zip(source, converted).allSatisfy({ $0 == $1 }) {
            return "₍\(source)₎"
        }
        return String(converted)
    }
}
