import Foundation

enum WhispFormatting {
    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func durationDescription(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours) ч \(minutes) мин"
        } else if minutes > 0 {
            return "\(minutes) мин \(secs) с"
        } else {
            return "\(secs) с"
        }
    }

    static func safePathComponent(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Без названия" : String(cleaned.prefix(120))
    }

    static func datedTitle(title: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        let datePrefix = formatter.string(from: date)

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression) != nil {
            return trimmed
        }
        if trimmed.isEmpty || trimmed == "Новая лекция" || trimmed == "Не определено" {
            return "\(datePrefix) — Новая лекция"
        }
        return "\(datePrefix) — \(trimmed)"
    }

    static let russianMonths = [
        1: "Январь", 2: "Февраль", 3: "Март", 4: "Апрель", 5: "Май", 6: "Июнь",
        7: "Июль", 8: "Август", 9: "Сентябрь", 10: "Октябрь", 11: "Ноябрь", 12: "Декабрь"
    ]

    static func lecturePath(for session: LectureSession, root: String) -> String {
        let date = session.startedAt ?? session.createdAt
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let month = russianMonths[calendar.component(.month, from: date)] ?? "Месяц"
        let day = String(format: "%02d", calendar.component(.day, from: date))
        return [root, String(year), month, day, safePathComponent(session.subject), safePathComponent(session.title)]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    static func formatMarkdownNotes(_ text: String) -> String {
        var s = text

        // 1. Remove lonely empty '#' lines (e.g. "#\n\n# Кратко") FIRST
        s = s.replacingOccurrences(
            of: #"(?m)^#{1,6}\s*$"#,
            with: "",
            options: .regularExpression
        )

        // 2. Fix spaced hashes (e.g. "# # 1." -> "## 1.")
        s = s.replacingOccurrences(
            of: #"(?m)^#\s+(#+)"#,
            with: "#$1",
            options: .regularExpression
        )

        // 3. Separate headings stuck to preceding text or punctuation (e.g. "систем## Основные" -> "систем\n\n## Основные")
        // NOTE: Use [^\n#] so that valid markdown headings like "##" or "###" are not split!
        s = s.replacingOccurrences(
            of: #"([^\n#])\s*(#{1,6})\s*"#,
            with: "$1\n\n$2 ",
            options: .regularExpression
        )
        // Ensure space after '#' for headings at start of line
        s = s.replacingOccurrences(
            of: #"(?m)^(#{1,6})([^\s#])"#,
            with: "$1 $2",
            options: .regularExpression
        )

        // 4. Headings stuck to subsequent content without newline:
        // Heading ending in '?' stuck to uppercase word: e.g. "## Что такое жизнь?Определение"
        s = s.replacingOccurrences(
            of: #"\?([А-ЯЁ])"#,
            with: "?\n\n$1",
            options: .regularExpression
        )
        // Heading ending in letter stuck to numbered list: e.g. "## Свойства живого1."
        s = s.replacingOccurrences(
            of: #"(#{1,6}\s+[^\d\n]+)(\d{1,2}\.\s+)"#,
            with: "$1\n\n$2",
            options: .regularExpression
        )
        // Heading ending in letter stuck to [[Wikilink]] (excluding bold **): e.g. "# Общая биология[[Общая биология]]"
        s = s.replacingOccurrences(
            of: #"(#{1,6}\s+[^\*\[\n]+)(\[\[)"#,
            with: "$1\n\n$2",
            options: .regularExpression
        )
        // Heading ending in letter/punctuation stuck to bullet item: e.g. "## Заголовок* "
        s = s.replacingOccurrences(
            of: #"(#{1,6}\s+[^\n]+?)(\s*\*\s+)"#,
            with: "$1\n\n* ",
            options: .regularExpression
        )

        // 5. Glued words in Russian (lowercase touching uppercase without space, e.g. "биологияОбщая", "актуальностьЛектор")
        s = s.replacingOccurrences(
            of: #"([а-яё])([А-ЯЁ])"#,
            with: "$1\n\n$2",
            options: .regularExpression
        )

        // 6. Separate bold sections and bullet lists stuck to preceding punctuation or asterisks:
        // Triple asterisks after punctuation before bold title: e.g. ".(или [[Биосистемы]]).***Важный момент:**"
        s = s.replacingOccurrences(
            of: #"([.!?»\)])\s*\*{3,}([^\*\n]+?\*\*)"#,
            with: "$1\n\n* **$2",
            options: .regularExpression
        )
        // Triple asterisks at start of line: e.g. "***Контекст:**"
        s = s.replacingOccurrences(
            of: #"(?m)^(\s*)\*{3,}([^\*\n]+?\*\*)"#,
            with: "$1* **$2",
            options: .regularExpression
        )
        // Bold section stuck to preceding punctuation: e.g. "последнего.**Неясные"
        s = s.replacingOccurrences(
            of: #"([.!?»\)])\s*(\*\*[А-ЯЁA-Z])"#,
            with: "$1\n\n$2",
            options: .regularExpression
        )
        // Bold title ending with 3+ asterisks (closes bold and starts bullet list):
        // e.g. "**[[Единство состава]]***   Наличие" -> "**[[Единство состава]]**\n\n* Наличие"
        // e.g. "**Неясные места/Вопросы:***   Лектор" -> "**Неясные места/Вопросы:**\n\n* Лектор"
        s = s.replacingOccurrences(
            of: #"(\*\*[^\*\n]+?)\*{3,}\s*"#,
            with: "$1**\n\n* ",
            options: .regularExpression
        )
        // Remaining stray triple asterisks
        s = s.replacingOccurrences(
            of: #"\*{3,}\s*"#,
            with: "**\n\n* ",
            options: .regularExpression
        )

        // 7. Separate list items stuck to text or punctuation
        // Numbered list items: e.g. "материала.1. " or "биологии]]:1. "
        s = s.replacingOccurrences(
            of: #"([.!?»\)\]]|[а-яё0-9])\s*(\d{1,2}\.\s+)"#,
            with: "$1\n\n$2",
            options: .regularExpression
        )
        // Colon stuck to list items: e.g. "включая:* " or "включая:1. "
        s = s.replacingOccurrences(
            of: #":\s*(\d{1,2}\.\s+)"#,
            with: ":\n\n$1",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #":\s*\*\s+"#,
            with: ":\n\n* ",
            options: .regularExpression
        )
        // Colon stuck to bold or capitalized text: e.g. "(XIX век):Способ"
        s = s.replacingOccurrences(
            of: #":([А-ЯЁ\[])"#,
            with: ":\n\n$1",
            options: .regularExpression
        )

        // Inline bullet item stuck to end of line / text / wikilinks (e.g. "\"Найти\".* NB!" or "учение]]* [[Экология]]"):
        s = s.replacingOccurrences(
            of: #"([\]\)\.\"»а-яёa-z0-9])\s*\*(?!\*)\s*([\[A-ZА-ЯЁ])"#,
            with: "$1\n\n* $2",
            options: .regularExpression
        )

        // 8. Sentences stuck together: punctuation followed by closing quote and/or Capital letter
        // e.g. "белков.\"Однако" -> "белков.\" Однако" or "средой.Эти" -> "средой. Эти"
        s = s.replacingOccurrences(
            of: #"([.!?][\"»]?)([А-ЯЁ])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"([»])([А-ЯЁ])"#,
            with: "$1 $2",
            options: .regularExpression
        )

        // 9. Fix accidental split bolding at start of line (e.g. "* *Способ" -> "**Способ")
        s = s.replacingOccurrences(
            of: #"(?m)^(\s*)\*\s+\*([^\s\*])"#,
            with: "$1**$2",
            options: .regularExpression
        )

        // 10. Fix numbered list with newline before bold item (e.g. "1.\n\n**Способ" -> "1. **Способ")
        s = s.replacingOccurrences(
            of: #"(?m)^(\d+\.)\s*\n+\s*(\*\*)"#,
            with: "$1 $2",
            options: .regularExpression
        )

        // 11. Normalize multiple empty lines to at most two newlines
        s = s.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
