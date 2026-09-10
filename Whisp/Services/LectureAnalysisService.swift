import Foundation

actor LectureAnalysisService {
    private let client: GeminiAPIClient
    private let model: String
    private let fallbackModels: [String]

    init(
        client: GeminiAPIClient,
        model: String,
        fallbackModel: String? = nil,
        fallbackModels: [String] = []
    ) {
        self.client = client
        self.model = model
        var candidates = fallbackModel.map { [$0] } ?? []
        candidates.append(contentsOf: fallbackModels)
        var seen = Set<String>()
        self.fallbackModels = candidates.compactMap { candidate in
            let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned != model, seen.insert(cleaned).inserted else { return nil }
            return cleaned
        }
    }

    struct LecturePart: Sendable {
        let index: Int
        let total: Int
        let start: Double
        let end: Double
        let text: String

        var timeRange: String {
            "\(WhispFormatting.timestamp(start)) – \(WhispFormatting.timestamp(end))"
        }
    }

    struct MetadataEnvelope: Codable, Sendable {
        var title: String
        var subject: String
        var confidence: Double
        var alternatives: [String]?
        var tags: [String]?
        var keyConcepts: [String]?
        var summary: String
    }

    func analyze(
        segments: [TranscriptSegment],
        subjects: [String],
        onStatus: (@Sendable (String) async -> Void)? = nil,
        onMetadata: (@Sendable (AnalysisResult) async -> Void)? = nil,
        onPartCompleted: (@Sendable (_ currentPart: Int, _ totalParts: Int, _ partText: String) async -> Void)? = nil
    ) async throws -> AnalysisResult {
        let sortedSegments = segments.sorted { $0.start < $1.start }
        guard !sortedSegments.isEmpty else {
            return AnalysisResult(
                title: "Новая лекция",
                subject: "Не определено",
                confidence: 0,
                alternatives: [],
                summary: "",
                detailedNotes: "",
                studentNotebook: "",
                tags: [],
                keyConcepts: []
            )
        }

        let fullTranscript = sortedSegments.map {
            "[\(WhispFormatting.timestamp($0.start))] \($0.speaker.map { "\($0): " } ?? "")\($0.text)"
        }.joined(separator: "\n")

        // 1. Быстрый этап метаданных (название, предмет, теги, краткая суть)
        await onStatus?("Определяем тему и предмет через \(model)...")
        let metadata = try await extractMetadata(transcript: fullTranscript, subjects: subjects, onStatus: onStatus)

        var partialResult = AnalysisResult(
            title: metadata.title,
            subject: metadata.subject,
            confidence: metadata.confidence,
            alternatives: metadata.alternatives ?? [],
            summary: metadata.summary,
            detailedNotes: "",
            studentNotebook: "",
            tags: metadata.tags ?? [],
            keyConcepts: metadata.keyConcepts ?? []
        )
        await onMetadata?(partialResult)

        // 2. Разбиение на части для прогрессивной генерации
        let parts = partitionSegments(sortedSegments)
        var generatedParts: [String] = []

        for part in parts {
            try Task.checkCancellation()
            if parts.count == 1 {
                await onStatus?("Пишем конспект лекции через \(model)...")
            } else {
                await onStatus?("Конспект: часть \(part.index) из \(part.total) (\(part.timeRange))...")
            }

            let partNotes = try await generatePartNotes(
                part: part,
                title: metadata.title,
                subject: metadata.subject,
                onStatus: onStatus
            )
            let formattedPart = WhispFormatting.formatMarkdownNotes(partNotes)
            generatedParts.append(formattedPart)
            await onPartCompleted?(part.index, part.total, formattedPart)
        }

        let combinedPartNotes = generatedParts.joined(separator: "\n\n")
        await onStatus?("Собираем части в единый конспект через \(model)...")

        let consolidatedNotes: String
        do {
            consolidatedNotes = try await consolidateNotes(
                title: metadata.title,
                subject: metadata.subject,
                summary: metadata.summary,
                parts: generatedParts,
                onStatus: onStatus
            )
        } catch {
            // The progressive parts are already useful. If the editorial pass
            // fails, keep them instead of turning a successful analysis into an
            // empty note.
            await onStatus?("Финальная сборка не удалась — сохраняем готовые части конспекта.")
            consolidatedNotes = combinedPartNotes
        }

        let formattedNotes = WhispFormatting.formatMarkdownNotes(consolidatedNotes)
        partialResult.studentNotebook = formattedNotes
        partialResult.detailedNotes = formattedNotes

        await onStatus?("Конспект готов")
        return partialResult
    }

    private func partitionSegments(_ segments: [TranscriptSegment]) -> [LecturePart] {
        let totalChars = segments.reduce(0) { $0 + $1.text.count }
        let totalDuration = (segments.last?.end ?? 0) - (segments.first?.start ?? 0)

        // Для коротких записей достаточно 1 части
        guard totalChars > 14_000 || totalDuration > 1_000 else {
            let text = segments.map {
                "[\(WhispFormatting.timestamp($0.start))] \($0.speaker.map { "\($0): " } ?? "")\($0.text)"
            }.joined(separator: "\n")
            return [LecturePart(
                index: 1,
                total: 1,
                start: segments.first?.start ?? 0,
                end: segments.last?.end ?? 0,
                text: text
            )]
        }

        // Целевой размер части: ~18 000 символов или ~15 минут аудио
        let targetCharsPerPart = 18_000
        let targetDurationPerPart = 1_000.0

        var groups: [[TranscriptSegment]] = []
        var currentGroup: [TranscriptSegment] = []
        var currentChars = 0
        var groupStartTime = segments.first?.start ?? 0

        for segment in segments {
            currentGroup.append(segment)
            currentChars += segment.text.count
            let elapsedInGroup = segment.end - groupStartTime

            if (currentChars >= targetCharsPerPart && elapsedInGroup >= 600) || elapsedInGroup >= targetDurationPerPart {
                groups.append(currentGroup)
                currentGroup = []
                currentChars = 0
                groupStartTime = segment.end
            }
        }
        if !currentGroup.isEmpty {
            if currentChars < 3_000, !groups.isEmpty {
                groups[groups.count - 1].append(contentsOf: currentGroup)
            } else {
                groups.append(currentGroup)
            }
        }

        let totalParts = max(1, groups.count)
        return groups.enumerated().map { index, groupSegments in
            let text = groupSegments.map {
                "[\(WhispFormatting.timestamp($0.start))] \($0.speaker.map { "\($0): " } ?? "")\($0.text)"
            }.joined(separator: "\n")
            return LecturePart(
                index: index + 1,
                total: totalParts,
                start: groupSegments.first?.start ?? 0,
                end: groupSegments.last?.end ?? (groupSegments.first?.start ?? 0),
                text: text
            )
        }
    }

    private func extractMetadata(
        transcript: String,
        subjects: [String],
        onStatus: (@Sendable (String) async -> Void)?
    ) async throws -> MetadataEnvelope {
        let sampleTranscript: String
        if transcript.count > 90_000 {
            let start = String(transcript.prefix(50_000))
            let end = String(transcript.suffix(30_000))
            sampleTranscript = "\(start)\n\n[...основная часть лекции...]\n\n\(end)"
        } else {
            sampleTranscript = transcript
        }

        let prompt = """
        Ты анализируешь расшифровку русской лекции для базы знаний Obsidian.
        Выбери наиболее подходящий предмет из списка: \(subjects.joined(separator: ", ")).

        Верни строго JSON со следующими ключами:
        - title: точное, ёмкое и понятное название темы лекции (без кавычек и дат)
        - subject: предмет из предложенного списка (или самый точный школьный/университетский предмет)
        - confidence: число от 0.0 до 1.0 (степень уверенности в определении предмета)
        - alternatives: массив до 3 альтернативных предметов
        - tags: массив из 3-6 тегов для Obsidian (например: ["лекция", "математика", "интегралы"])
        - keyConcepts: массив из 3-7 ключевых понятий и терминов для графа связей Obsidian (например: ["Определенный интеграл", "Формула Ньютона-Лейбница"])
        - summary: краткая суть лекции (1-2 ёмких абзаца без воды)

        РАСШИФРОВКА:
        \(sampleTranscript)
        """

        let schema: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "title": ["type": "STRING", "description": "Точное название темы лекции"],
                "subject": ["type": "STRING", "description": "Название учебного предмета"],
                "confidence": ["type": "NUMBER", "description": "Уверенность (0...1)"],
                "alternatives": ["type": "ARRAY", "items": ["type": "STRING"], "description": "До 3 альтернативных предметов"],
                "tags": ["type": "ARRAY", "items": ["type": "STRING"], "description": "Массив из 3-6 тегов для Obsidian"],
                "keyConcepts": ["type": "ARRAY", "items": ["type": "STRING"], "description": "Массив из 3-7 ключевых понятий"],
                "summary": ["type": "STRING", "description": "Краткая суть лекции (1-2 абзаца)"]
            ],
            "required": ["title", "subject", "confidence", "alternatives", "tags", "keyConcepts", "summary"]
        ]

        let text = try await generateText(prompt: prompt, responseSchema: schema, onStatus: onStatus)
        do {
            return try JSONDecoder().decode(MetadataEnvelope.self, from: Data(text.utf8))
        } catch {
            return MetadataEnvelope(
                title: "Лекция (\(subjects.first ?? "Новая"))",
                subject: subjects.first ?? "Не определено",
                confidence: 0.5,
                alternatives: [],
                tags: ["лекция"],
                keyConcepts: [],
                summary: "Конспект лекции."
            )
        }
    }

    private func generatePartNotes(
        part: LecturePart,
        title: String,
        subject: String,
        onStatus: (@Sendable (String) async -> Void)?
    ) async throws -> String {
        let partInfo = part.total > 1
            ? "часть \(part.index) из \(part.total) (интервал: \(part.timeRange))"
            : "вся лекция"

        let prompt = """
        Ты оформляешь конспект русской лекции для базы знаний Obsidian.
        Тема всей лекции: «\(title)». Предмет: \(subject).
        Текущий фрагмент: \(partInfo).

        Сгенерируй полноценный конспект для СТУДЕНЧЕСКОЙ ТЕТРАДИ («ПОД ЗАПИСЬ»).
        Представь, что ты внимательный студент-отличник, который пишет конспект в тетрадь ручкой прямо на паре.

        КРИТИЧЕСКИЕ ТРЕБОВАНИЯ ДЛЯ ТЕТРАДИ:
        - АБСОЛЮТНО НИКАКОЙ ВОДЫ И МЕТА-ТЕКСТА: категорически запрещено писать «Лектор объяснил», «Преподаватель поприветствовал», «Студенты спросили», «В ходе пары обсуждалось», «В этой части рассматривается».
        - Пиши строго то, что диктуется или пишется на доске:
          * Заголовок темы или раздела (## ...)
          * **Определения и правила** (чёткие формулировки под диктовку)
          * **Классификации и алгоритмы** (аккуратными списками)
          * **Формулы и дроби** (строго в красивом LaTeX формате, см. правила ниже)
          * **Примеры решений с пошаговыми выкладками**
          * **NB! / Важно к экзамену**
        - Ключевые термины оборачивай в вики-ссылки Obsidian: [[Термин]] или [[Термин|склонение]].

        КРИТИЧЕСКИЕ ПРАВИЛА ОФОРМЛЕНИЯ МАТЕМАТИКИ И ФОРМУЛ (LATEX ДЛЯ OBSIDIAN):
        - Obsidian идеально поддерживает LaTeX! Все математические формулы, дроби, уравнения, системы и матрицы оформляй СТРОГО в LaTeX:
          * ДРОБИ: пиши ТОЛЬКО через `\\frac{числитель}{знаменатель}`. Категорически запрещено писать дроби косой чертой типа `5/2`!
          * ОПРЕДЕЛИТЕЛИ И МАТРИЦЫ: пиши через `\\begin{vmatrix} ... \\end{vmatrix}` или `\\begin{pmatrix} ... \\end{pmatrix}`.
          * СИСТЕМЫ УРАВНЕНИЙ: пиши через `\\begin{cases} ... \\end{cases}`.
          * ЗНАКИ: используй `\\cdot` для умножения (не пиши `*`), `\\pm`, `\\ne`, `\\Delta`, `\\sqrt{...}`, `\\in`.
          * Крупные формулы выноси в отдельные блоки `$$ ... $$` с пустой строкой до и после. Короткие формулы в тексте оборачивай в одинарные доллары `$ ... $`.

        КРИТИЧЕСКИЕ ПРАВИЛА ВЁРСТКИ (MARKDOWN):
        - Каждый пункт списка (начинающийся с *, - или 1., 2.) ОБЯЗАТЕЛЬНО должен начинаться с НОВОЙ СТРОКИ.
        - Перед каждым заголовком (## или ###) делай пустую строку.
        - Разделяй смысловые блоки пустой строкой (\\n\\n).

        Верни только готовый текст Markdown без вступительных и заключительных комментариев от себя.

        РАСШИФРОВКА ЭТОГО ФРАГМЕНТА:
        \(part.text)
        """

        return try await generateText(prompt: prompt, responseSchema: nil, onStatus: onStatus)
    }

    private func consolidateNotes(
        title: String,
        subject: String,
        summary: String,
        parts: [String],
        onStatus: (@Sendable (String) async -> Void)?
    ) async throws -> String {
        let source = parts.enumerated().map { index, part in
            "### Часть \(index + 1)\n\(part)"
        }.joined(separator: "\n\n")

        let prompt = """
        Ты — старший редактор конспекта русской лекции для базы знаний Obsidian.
        Ниже переданы части одного и того же конспекта, созданные по отдельности.
        Объедини их в ОДИН цельный, последовательный и нормальный текст.

        Тема: «\(title)». Предмет: \(subject).
        Краткая суть для ориентира: \(summary)

        Правила финальной сборки:
        - Не добавляй факты, которых нет в исходных частях.
        - Удали повторы, дублирующиеся заголовки и обрывки фраз на границах частей.
        - Сохрани все важные определения, формулы, шаги решений, классификации и примеры.
        - Сохрани полезные LaTeX-формулы и wiki-ссылки Obsidian.
        - Выстрой материал в логичном порядке, чтобы текст читался как единый конспект, а не как склейка фрагментов.
        - Не пиши мета-текст вроде «в первой части», «вторая часть», «нейросеть» или «лектор рассказал».
        - Верни только готовый Markdown-конспект без вступления и заключения от себя.

        ИСХОДНЫЕ ЧАСТИ:
        \(source)
        """

        return try await generateText(prompt: prompt, responseSchema: nil, onStatus: onStatus)
    }

    private func generateText(
        prompt: String,
        responseSchema: [String: Any]?,
        onStatus: (@Sendable (String) async -> Void)?
    ) async throws -> String {
        try await client.generateText(
            prompt: prompt,
            model: model,
            fallbackModels: fallbackModels,
            responseSchema: responseSchema,
            onStatus: onStatus
        )
    }
}
