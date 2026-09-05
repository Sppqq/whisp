import Foundation

struct MarkdownBundle: Sendable {
    var raw: String
    var final: String
    var notes: String
    var studentNotebook: String
    var quiz: String = ""
}

enum MarkdownExporter {
    static func render(session: LectureSession) -> MarkdownBundle {
        let status = session.hasPendingBackfill ? "local_fallback" : "complete"
        let audio = audioLinks(session: session)
        let mainYaml = yaml(session: session, transcriptionStatus: status, isMainNote: true)
        let subYaml = yaml(session: session, transcriptionStatus: status, isMainNote: false)
        let rawBody = transcriptBody(session.rawTranscript)
        let finalBody = transcriptBody(session.finalTranscript)
        let notesBody = WhispFormatting.formatMarkdownNotes(session.analysis.map(renderAnalysis) ?? session.notesMarkdown)
        let studentBody = WhispFormatting.formatMarkdownNotes(session.analysis.map(renderStudentNotebook) ?? (session.studentNotesMarkdown.isEmpty ? notesBody : session.studentNotesMarkdown))

        let transcriptSection: String
        if !finalBody.isEmpty {
            let quoted = finalBody.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
            transcriptSection = """
            \n---\n
            > [!example]- 🎙️ Полная стенограмма пары с таймкодами (развернуть)
            \(quoted)
            """
        } else {
            transcriptSection = ""
        }

        let mainContent = """
        \(mainYaml)
        # \(session.title)

        \(graphNavigation(session: session, includeTags: true))

        \(audio)

        \(studentBody)
        """

        let quizContent = session.quizMarkdown.isEmpty ? "" : "\(subYaml)\n# \(session.title) — Вопросы к зачёту\n\n\(session.quizMarkdown)\n"

        return MarkdownBundle(
            raw: "\(subYaml)\n# \(session.title) — Сырой звук\n\n\(rawBody)\n",
            final: "\(subYaml)\n# \(session.title) — Стенограмма\n\n\(finalBody)\n",
            notes: "\(subYaml)\n# \(session.title) — Разбор нейросетью\n\n\(notesBody)\n",
            studentNotebook: mainContent,
            quiz: quizContent
        )
    }

    private static func yaml(session: LectureSession, transcriptionStatus: String, isMainNote: Bool) -> String {
        let iso = ISO8601DateFormatter().string(from: session.startedAt ?? session.createdAt)
        let fallback = session.fallbackIntervals.map {
            "\(WhispFormatting.timestamp($0.start))-\(WhispFormatting.timestamp($0.end ?? session.duration))"
        }.joined(separator: ", ")

        if !isMainNote {
            return """
            ---
            type: transcript
            date: \(iso)
            duration_seconds: \(Int(session.duration))
            title: "\(escapeYAML(session.title))"
            transcription_status: \(transcriptionStatus)
            fallback_intervals: "\(fallback)"
            ---
            """
        }

        var tagsSection = ""
        let tags = sessionTags(session: session)
        if !tags.isEmpty {
            let tagsYaml = tags.map { "  - \($0)" }.joined(separator: "\n")
            tagsSection = "\ntags:\n\(tagsYaml)"
        }

        let subjectLink = session.subject != "Не определено" ? "\"\(escapeYAML(session.subject))\"" : "\"Не определено\""

        return """
        ---
        type: lecture
        date: \(iso)
        duration_seconds: \(Int(session.duration))
        subject: \(subjectLink)
        title: "\(escapeYAML(session.title))"
        transcription_status: \(transcriptionStatus)\(tagsSection)
        transcription_models: [gemini-3.5-transcribe-live, large-v3-v20240930_626MB]
        fallback_intervals: "\(fallback)"
        audio: \(session.captureSystemAudio ? "[Микрофон.m4a, Системный звук.m4a]" : "[Микрофон.m4a]")
        ---
        """
    }

    private static func sessionTags(session: LectureSession) -> [String] {
        var tags: [String] = []
        if session.subject != "Не определено" {
            let sTag = cleanTag(session.subject)
            if !sTag.isEmpty { tags.append(sTag) }
        }
        let date = session.startedAt ?? session.createdAt
        let calendar = Calendar(identifier: .gregorian)
        let monthNum = calendar.component(.month, from: date)
        if let monthName = WhispFormatting.russianMonths[monthNum]?.lowercased() {
            let mTag = cleanTag(monthName)
            if !mTag.isEmpty { tags.append(mTag) }
        }
        return tags
    }

    private static func graphNavigation(session: LectureSession, includeTags: Bool) -> String {
        var lines: [String] = []
        if session.subject != "Не определено" {
            lines.append("- **Предмет**: \(session.subject)")
        }
        if let concepts = session.analysis?.keyConcepts, !concepts.isEmpty {
            let links = concepts.map { "[[\($0)]]" }.joined(separator: ", ")
            lines.append("- **Ключевые понятия**: \(links)")
        }

        if includeTags {
            let tags = sessionTags(session: session)
            let tagPills = tags.map { "#\($0)" }
            if !tagPills.isEmpty {
                lines.append("- **Теги**: \(tagPills.joined(separator: " "))")
            }
        }

        return """
        > [!abstract] 🔗 Связи в Obsidian
        > \(lines.joined(separator: "\n> "))
        """
    }

    private static func transcriptBody(_ segments: [TranscriptSegment]) -> String {
        segments.sorted { $0.start < $1.start }.map { segment in
            let speaker = segment.speaker.map { "**\($0):** " } ?? ""
            let fallback = segment.source == .whisperFallback ? " `локальная страховка`" : ""
            return "[\(WhispFormatting.timestamp(segment.start))] \(speaker)\(segment.text)\(fallback)"
        }.joined(separator: "\n\n")
    }

    private static func renderStudentNotebook(_ analysis: AnalysisResult) -> String {
        let text = analysis.studentNotebook.isEmpty ? analysis.detailedNotes : analysis.studentNotebook
        var result = """
        > [!note] ✍️ Студенческий конспект (под запись)
        > Записано строго по существу лекции без лишних вводных слов и мета-описаний.

        \(text)
        """
        if !analysis.keyConcepts.isEmpty {
            let items = analysis.keyConcepts.map { "- [[\($0)]]" }.joined(separator: "\n")
            result += """


            ## 🧠 Связанные понятия на графе

            \(items)
            """
        }
        return result
    }

    private static func renderAnalysis(_ analysis: AnalysisResult) -> String {
        var result = """
        ## Кратко

        \(analysis.summary)

        ## Подробный разбор лекции

        \(analysis.detailedNotes)
        """
        if !analysis.keyConcepts.isEmpty {
            let items = analysis.keyConcepts.map { "- [[\($0)]]" }.joined(separator: "\n")
            result += """


            ## 🧠 Связанные понятия на графе

            \(items)
            """
        }
        return result
    }

    private static func audioLinks(session: LectureSession) -> String {
        var links = ["![[Микрофон.m4a]]"]
        if session.captureSystemAudio { links.append("![[Системный звук.m4a]]") }
        return links.joined(separator: "\n")
    }

    private static func cleanTag(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "/" }
    }

    private static func escapeYAML(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
