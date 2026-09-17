import SwiftUI

/// Lightweight native Markdown renderer for iPhone. It keeps headings, lists,
/// emphasis, links, code and block quotes readable without shipping a web view.
struct MobileMarkdownView: View {
    let markdown: String

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.readableMarkdown(markdown).components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Spacer().frame(height: 3)
                } else {
                    lineView(line)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("### ") {
            markdownText(String(trimmed.dropFirst(4))).font(.headline).padding(.top, 6)
        } else if trimmed.hasPrefix("## ") {
            markdownText(String(trimmed.dropFirst(3))).font(.title3.bold()).padding(.top, 8)
        } else if trimmed.hasPrefix("# ") {
            markdownText(String(trimmed.dropFirst(2))).font(.title2.bold()).padding(.top, 10)
        } else if trimmed.hasPrefix("> ") {
            HStack(alignment: .top, spacing: 8) {
                Capsule().fill(.tint).frame(width: 3)
                markdownText(String(trimmed.dropFirst(2))).foregroundStyle(.secondary)
            }
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.range(of: "^\\d+[.)] ", options: .regularExpression) != nil {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.tint).fontWeight(.bold)
                markdownText(trimmed.replacingOccurrences(of: "^([-*]|\\d+[.)])\\s+", with: "", options: .regularExpression))
            }
        } else {
            markdownText(trimmed)
        }
    }

    private func markdownText(_ value: String) -> Text {
        if let attributed = try? AttributedString(markdown: value, options: .init(interpretedSyntax: .full)) {
            return Text(attributed)
        }
        return Text(value)
    }

    private static func readableMarkdown(_ value: String) -> String {
        var text = value
        if text.hasPrefix("---"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) {
            text = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = text
            .replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
            .replacingOccurrences(of: "\\text{", with: "")
            .replacingOccurrences(of: "\\cdot", with: "·")
            .replacingOccurrences(of: "\\approx", with: "≈")
            .replacingOccurrences(of: "\\rightarrow", with: "→")
            .replacingOccurrences(of: "\\times", with: "×")
            .replacingOccurrences(of: "$$", with: "")
            .replacingOccurrences(of: "$", with: "")
        text = text.replacingOccurrences(of: "\\", with: "")
        return text
    }
}
