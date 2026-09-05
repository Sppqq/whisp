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
        .background(Color(nsColor: .textBackgroundColor))
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
            } else if line.hasPrefix(">") {
                finishParagraph()
                blocks.append(.quote(stripQuote(line)))
            } else if let attachment = attachmentName(from: line) {
                finishParagraph()
                blocks.append(.attachment(attachment))
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

    private static func attachmentName(from line: String) -> String? {
        guard line.hasPrefix("![["), line.hasSuffix("]]"), line.count > 5 else { return nil }
        return String(line.dropFirst(3).dropLast(2))
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
            .background(WhispPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        case .attachment(let name):
            Label(MarkdownDisplayFormatting.cleanWikiText(name), systemImage: "paperclip")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(WhispPalette.panel, in: RoundedRectangle(cornerRadius: 9))
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
            "\\uparrow": "↑", "\\downarrow": "↓", "\\rightarrow": "→",
            "\\leftarrow": "←", "\\cdot": "·", "\\times": "×",
            "\\Delta": "Δ", "\\leq": "≤", "\\geq": "≥", "\\neq": "≠",
            "\\pm": "±", "\\left": "", "\\right": ""
        ]
        for (source, replacement) in symbols {
            value = value.replacingOccurrences(of: source, with: replacement)
        }
        return value
            .replacingOccurrences(of: "\\(", with: "")
            .replacingOccurrences(of: "\\)", with: "")
            .replacingOccurrences(of: "$", with: "")
    }
}
