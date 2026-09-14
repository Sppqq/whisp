import Foundation

struct MarkdownBundle: Sendable {
    var raw: String
    var final: String
    var notes: String
    var studentNotebook: String
    var quiz: String = ""
}

enum MarkdownExporter {
    /// Builds the content shown in the student-notebook preview.
    ///
    /// Older sessions may only store the generated notebook text, while newer
    /// exported notes already contain the Obsidian navigation callout and audio
    /// attachment. Keep the preview consistent in both cases without adding a
    /// second copy of either block.
    static func reviewStudentNotebook(session: LectureSession) -> String {
        let stored = session.studentNotesMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = stored.isEmpty
            ? session.analysis.map { renderStudentNotebook($0) } ?? ""
            : stored
        guard !body.isEmpty else { return "" }
        let bodyWithReminders = addingReminders(to: body, session: session)

        let hasNavigation = bodyWithReminders.contains("> [!abstract]")
        let hasAudio = bodyWithReminders.contains("![[Микрофон.m4a]]") || bodyWithReminders.contains("![[Системный звук.m4a]]")
        let additions = [
            hasNavigation ? nil : graphNavigation(session: session, includeTags: true),
            hasAudio ? nil : audioLinks(session: session)
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard !additions.isEmpty else { return bodyWithReminders }
        let inserted = additions.joined(separator: "\n\n")

        // Preserve frontmatter at the beginning so MarkdownPreview can hide it.
        let lines = bodyWithReminders.components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let closing = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            let closingOffset = closing + 1
            let frontmatter = lines[...closingOffset].joined(separator: "\n")
            let remainder = lines.dropFirst(closingOffset + 1).joined(separator: "\n")
            return [frontmatter, insertAfterTitleIfNeeded(remainder, inserted)]
                .joined(separator: "\n\n")
        }

        return insertAfterTitleIfNeeded(bodyWithReminders, inserted)
    }

    private static func insertAfterTitleIfNeeded(_ body: String, _ inserted: String) -> String {
        let lines = body.components(separatedBy: .newlines)
        if let firstContent = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[firstContent].trimmingCharacters(in: .whitespaces).hasPrefix("# ") {
            var result = lines
            result.insert(contentsOf: ["", inserted, ""], at: firstContent + 1)
            return result.joined(separator: "\n")
        }
        return "\(inserted)\n\n\(body)"
    }

    static func render(session: LectureSession, availableAudio: Set<String>? = nil) -> MarkdownBundle {
        let status = session.hasPendingBackfill ? "local_fallback" : "complete"
        let audio = audioLinks(session: session, availableAudio: availableAudio)
        let mainYaml = yaml(
            session: session,
            transcriptionStatus: status,
            isMainNote: true,
            availableAudio: availableAudio
        )
        let subYaml = yaml(session: session, transcriptionStatus: status, isMainNote: false)
        let rawBody = transcriptBody(session.rawTranscript)
        let finalBody = transcriptBody(session.finalTranscript)
        let notesBody: String
        if let storedNotes = storedMarkdownBody(session.notesMarkdown) {
            notesBody = WhispFormatting.formatMarkdownNotes(addingReminders(to: storedNotes, session: session))
        } else if let analysis = session.analysis {
            notesBody = WhispFormatting.formatMarkdownNotes(renderAnalysis(analysis))
        } else {
            notesBody = ""
        }

        let studentBody: String
        if let storedStudentNotes = storedMarkdownBody(session.studentNotesMarkdown) {
            studentBody = WhispFormatting.formatMarkdownNotes(addingReminders(to: storedStudentNotes, session: session))
        } else if let analysis = session.analysis {
            studentBody = WhispFormatting.formatMarkdownNotes(renderStudentNotebook(analysis))
        } else {
            studentBody = notesBody
        }

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

    private static func yaml(
        session: LectureSession,
        transcriptionStatus: String,
        isMainNote: Bool,
        availableAudio: Set<String>? = nil
    ) -> String {
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

        let audioFiles = audioFileNames(session: session, availableAudio: availableAudio)
        let audioValue = audioFiles.isEmpty ? "[]" : "[\(audioFiles.joined(separator: ", "))]"

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
        audio: \(audioValue)
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
        result += remindersMarkdown(analysis.reminders)
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
        result += remindersMarkdown(analysis.reminders)
        return result
    }

    private static func addingReminders(to body: String, session: LectureSession) -> String {
        guard let reminders = session.analysis?.reminders,
              !reminders.isEmpty,
              !body.contains("Задания к следующему уроку") else { return body }
        return body + remindersMarkdown(reminders)
    }

    private static func remindersMarkdown(_ reminders: [ReminderDraft]) -> String {
        guard !reminders.isEmpty else { return "" }
        let items = reminders.map { reminder in
            "- **\(reminder.title)**\n  \(reminder.notes)"
        }.joined(separator: "\n")
        return """


        ## ✅ Задания к следующему уроку

        \(items)
        """
    }

    private static func audioLinks(session: LectureSession, availableAudio: Set<String>? = nil) -> String {
        audioFileNames(session: session, availableAudio: availableAudio)
            .map { "![[\($0)]]" }
            .joined(separator: "\n")
    }

    private static func audioFileNames(session: LectureSession, availableAudio: Set<String>? = nil) -> [String] {
        var names = ["Микрофон.m4a"]
        if session.captureSystemAudio { names.append("Системный звук.m4a") }
        guard let availableAudio else { return names }
        return names.filter { availableAudio.contains($0) }
    }

    /// Stored markdown may come from a restored WebDAV document and therefore
    /// already contain frontmatter. Keep only its body before adding the
    /// current session properties, otherwise every sync would duplicate the
    /// Properties block in Obsidian.
    private static func storedMarkdownBody(_ text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            let body = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : body
        }

        guard let closingIndex = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
        }) else {
            let body = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : body
        }

        let bodyStart = closingIndex + 1
        let body = lines[bodyStart...].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
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
