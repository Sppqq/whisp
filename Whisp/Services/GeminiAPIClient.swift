import Foundation

actor GeminiAPIClient {
    struct UploadedFile: Decodable, Sendable {
        let name: String
        let uri: String
        let mimeType: String?
        let state: String?
        var uploadedWithKey: String?
    }

    private var apiKeys: [String]
    private var currentKeyIndex: Int = 0
    private let session: URLSession
    private let proxyDelegate: ProxyAuthenticationDelegate?
    private let baseURL = URL(string: "https://generativelanguage.googleapis.com")!

    init(apiKeys: [String], proxy: ProxyConfiguration) {
        let cleaned = apiKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.apiKeys = cleaned.isEmpty ? [""] : cleaned
        self.currentKeyIndex = 0
        let proxyDelegate = ProxyTransport.authenticationDelegate(proxy: proxy)
        self.proxyDelegate = proxyDelegate
        let configuration = ProxyTransport.sessionConfiguration(proxy: proxy)
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 900
        self.session = URLSession(
            configuration: configuration,
            delegate: proxyDelegate,
            delegateQueue: nil
        )
    }

    init(apiKey: String, proxy: ProxyConfiguration) {
        self.init(apiKeys: [apiKey], proxy: proxy)
    }

    func currentAPIKey() -> String {
        guard !apiKeys.isEmpty else { return "" }
        return apiKeys[currentKeyIndex % apiKeys.count]
    }

    func rotateToNextKey() -> (key: String, index: Int, previousIndex: Int, total: Int)? {
        guard apiKeys.count > 1 else { return nil }
        let prev = (currentKeyIndex % apiKeys.count) + 1
        currentKeyIndex = (currentKeyIndex + 1) % apiKeys.count
        let next = (currentKeyIndex % apiKeys.count) + 1
        return (apiKeys[currentKeyIndex], next, prev, apiKeys.count)
    }

    func checkModel(_ model: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "v1beta/models/\(model)"))
        request.setValue(currentAPIKey(), forHTTPHeaderField: "x-goog-api-key")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    func probeTranscription(_ model: String) async throws {
        try await probeKey(currentAPIKey(), model: model)
    }

    func probeKey(_ key: String, model: String) async throws {
        let wav = Self.silentWAV(duration: 0.2, sampleRate: 16_000)
        let body = GeminiTranscriptionPayload.request(model: model, audio: [
            "type": "audio", "mime_type": "audio/wav", "data": wav.base64EncodedString()
        ])
        _ = try await sendJSON(body, path: "v1beta/interactions", apiKeyOverride: key)
    }

    func analyze(
        transcript: String,
        subjects: [String],
        model: String,
        onStatus: (@Sendable (String) async -> Void)? = nil
    ) async throws -> AnalysisResult {
        let prompt = """
        Ты оформляешь расшифровку русской лекции для базы знаний Obsidian. Не добавляй знания от себя.
        Выбери предмет только из списка: \(subjects.joined(separator: ", ")).

        Сгенерируй ДВА независимых варианта конспекта:
        1) studentNotebook: СТУДЕНЧЕСКАЯ ТЕТРАДЬ («ПОД ЗАПИСЬ»).
           Представь, что ты внимательный студент-отличник, который сидит в аудитории и пишет конспект в тетрадь ручкой.
           КРИТИЧЕСКИЕ ТРЕБОВАНИЯ ДЛЯ ТЕТРАДИ:
           - АБСОЛЮТНО НИКАКОЙ ВОДЫ И МЕТА-ТЕКСТА: категорически запрещено писать «Лектор объяснил», «Преподаватель поприветствовал», «Студенты спросили», «В ходе пары обсуждалось».
           - Пиши строго то, что диктуется или пишется на доске:
             * Заголовки тем и подтем
             * **Определения и правила** (чёткие формулировки под диктовку)
             * **Классификации и алгоритмы** (аккуратными списками)
             * **Формулы и дроби** (строго в красивом LaTeX формате, см. правила ниже)
             * **Примеры решений с пошаговыми выкладками**
             * **NB! / Важно к экзамену**
           - Ключевые термины оборачивай в вики-ссылки Obsidian: [[Термин]] или [[Термин|склонение]].

        2) detailedNotes: ПОДРОБНЫЙ АНАЛИТИЧЕСКИЙ РАЗБОР.
           Развернутый аналитический конспект с разделами: подробное изложение тем, контекст, разобранные задания, вопросы и неясные места лекции. С вики-ссылками [[Термин]].

        КРИТИЧЕСКИЕ ПРАВИЛА ОФОРМЛЕНИЯ МАТЕМАТИКИ И ФОРМУЛ (LATEX ДЛЯ OBSIDIAN):
        - Obsidian идеально поддерживает LaTeX! Все математические формулы, дроби, уравнения, системы и матрицы оформляй СТРОГО в LaTeX:
          * ДРОБИ: пиши ТОЛЬКО через `\\frac{числитель}{знаменатель}`. Категорически запрещено писать дроби косой чертой типа `y = 5/2 x - 7/2`! Всегда пиши: `$y = \\frac{5}{2}x - \\frac{7}{2}$`.
          * ОПРЕДЕЛИТЕЛИ И МАТРИЦЫ: пиши ТОЛЬКО через `\\begin{vmatrix} ... \\end{vmatrix}` или `\\begin{pmatrix} ... \\end{pmatrix}`:
            $$\\Delta = \\begin{vmatrix} 5 & -2 \\\\ 3 & 4 \\end{vmatrix} = 5 \\cdot 4 - (-2) \\cdot 3 = 26$$
            КАТЕГОРИЧЕСКИ ЗАПРЕЩЕНО рисовать матрицы текстовыми палочками вроде `| 5 -2 |` на разных строках!
          * СИСТЕМЫ УРАВНЕНИЙ: пиши через `\\begin{cases} ... \\end{cases}`.
          * ЗНАКИ: используй `\\cdot` для знака умножения (не используй `*`), `\\pm` для плюс-минуса, `\\ne` для не равно, `\\Delta` для дельты, `\\sqrt{...}` для корней, `\\in` для принадлежности интервалу.
          * Крупные или ключевые формулы выноси в отдельные блоки `$$ ... $$` с пустой строкой до и после. Короткие формулы в тексте оборачивай в одинарные доллары `$ ... $`.

        КРИТИЧЕСКИЕ ПРАВИЛА ВЁРСТКИ И СТРУКТУРЫ (MARKDOWN):
        - Каждый пункт списка (начинающийся с *, - или 1., 2.) ОБЯЗАТЕЛЬНО должен начинаться с НОВОЙ СТРОКИ (\\n). КАТЕГОРИЧЕСКИ ЗАПРЕЩЕНО писать пункты списка в одну строку!
        - Перед каждым заголовком (## или ###) ОБЯЗАТЕЛЬНО делай пустую строку (\\n\\n## ...). Никогда не ставь пустой символ `#` на отдельной строке.
        - Нумерованные списки пиши слитным маркером с жирным текстом: `1. **Тема:** описание`, без разрыва строки между цифрой и текстом.
        - Подпункты (Пример, NB!, Ошибка, Правило) пиши с новой строки с отступом (вложенный список).
        - Разделяй смысловые блоки пустой строкой (\\n\\n).

        Верни строго JSON со следующими ключами:
        - title: точное название темы лекции
        - subject: предмет
        - confidence: уверенность (0...1)
        - alternatives: до 3 альтернативных предметов
        - tags: массив из 3-6 тегов для Obsidian (например: ["лекция", "химия", "таблица_менделеева", "молярная_масса"])
        - keyConcepts: массив из 3-7 ключевых понятий и терминов для графа связей Obsidian (например: ["Таблица Менделеева", "Молярная масса", "Химические элементы"])
        - summary: краткая суть лекции (1-2 абзаца)
        - studentNotebook: текст студенческой тетради под запись
        - detailedNotes: подробный аналитический разбор лекции

        РАСШИФРОВКА:
        \(transcript)
        """
        let schema: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "title": ["type": "STRING", "description": "Точное название темы лекции"],
                "subject": ["type": "STRING", "description": "Название учебного предмета"],
                "confidence": ["type": "NUMBER", "description": "Уверенность в определении предмета (0...1)"],
                "alternatives": ["type": "ARRAY", "items": ["type": "STRING"], "description": "До 3 альтернативных предметов"],
                "tags": ["type": "ARRAY", "items": ["type": "STRING"], "description": "Массив из 3-6 тегов для Obsidian"],
                "keyConcepts": ["type": "ARRAY", "items": ["type": "STRING"], "description": "Массив из 3-7 ключевых понятий для Obsidian"],
                "summary": ["type": "STRING", "description": "Краткая суть лекции (1-2 абзаца). Используй переносы строк \\n\\n между абзацами."],
                "studentNotebook": [
                    "type": "STRING",
                    "description": "Полноценный многострочный конспект в формате Markdown для студенческой тетради. ОБЯЗАТЕЛЬНО используй двойные переносы строк (\\n\\n) перед заголовками, пунктами списков и между абзацами. Не склеивай слова и заголовки в одну строку!"
                ],
                "detailedNotes": [
                    "type": "STRING",
                    "description": "Подробный многострочный аналитический разбор лекции в формате Markdown. ОБЯЗАТЕЛЬНО используй двойные переносы строк (\\n\\n) перед заголовками, пунктами списков и между абзацами. Не склеивай строки и слова!"
                ]
            ],
            "required": ["title", "subject", "confidence", "alternatives", "summary", "detailedNotes"]
        ]
        let text = try await generateText(prompt: prompt, model: model, responseSchema: schema, onStatus: onStatus)
        let envelope = try JSONDecoder().decode(GeminiAnalysisEnvelope.self, from: Data(text.utf8))
        return AnalysisResult(
            title: envelope.title,
            subject: envelope.subject,
            confidence: envelope.confidence,
            alternatives: envelope.alternatives,
            summary: envelope.summary,
            detailedNotes: WhispFormatting.formatMarkdownNotes(envelope.detailedNotes),
            studentNotebook: WhispFormatting.formatMarkdownNotes(envelope.studentNotebook ?? envelope.detailedNotes),
            tags: envelope.tags ?? [],
            keyConcepts: envelope.keyConcepts ?? []
        )
    }

    func generateText(
        prompt: String,
        model: String,
        responseSchema: [String: Any]? = nil,
        onStatus: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        let maxAttempts = max(5, apiKeys.count * 3)
        var lastError: Error?

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            let key = currentAPIKey()
            let effectiveModel = (attempt > apiKeys.count && model == "gemini-3.8-flash") ? "gemini-2.5-flash" : model
            do {
                var generation: [String: Any] = ["temperature": 0.2]
                if let responseSchema {
                    generation["responseMimeType"] = "application/json"
                    generation["responseSchema"] = responseSchema
                }
                let body: [String: Any] = [
                    "contents": [["role": "user", "parts": [["text": prompt]]]],
                    "generationConfig": generation
                ]
                let data = try await sendJSON(body, path: "v1beta/models/\(effectiveModel):generateContent", apiKeyOverride: key)
                return try extractText(data)
            } catch let error as GeminiAPIError where error.isRateLimitOrQuota {
                lastError = error
                if attempt == maxAttempts { throw error }

                if let rotation = rotateToNextKey() {
                    await onStatus?("Лимит квоты на ключе #\(rotation.previousIndex). Переключаемся на ключ #\(rotation.index) из \(rotation.total)...")
                    try? await Task.sleep(for: .milliseconds(400))
                } else {
                    let delay = max(3.0, (error.retryAfter ?? 10.0) + 1.0)
                    let delayFormatted = String(format: "%.1f", delay)
                    await onStatus?("Превышен лимит запросов Google API. Ожидание \(delayFormatted) сек перед повтором...")
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }
        throw lastError ?? GeminiAPIError(code: 429, status: "RESOURCE_EXHAUSTED", message: "Превышен лимит запросов к Gemini", retryAfter: 10)
    }

    func transcribe(
        audioURL: URL,
        model: String,
        vocabulary: [String] = [],
        onStatus: (@Sendable (String) async -> Void)? = nil
    ) async throws -> [TranscriptSegment] {
        let maxAttempts = max(5, apiKeys.count * 3)
        var lastError: Error?

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                return try await performTranscribe(audioURL: audioURL, model: model, onStatus: onStatus)
            } catch let error as GeminiAPIError where error.isRateLimitOrQuota {
                lastError = error
                if attempt == maxAttempts { throw error }

                if let rotation = rotateToNextKey() {
                    await onStatus?("Лимит квоты на ключе #\(rotation.previousIndex). Переключаемся на ключ #\(rotation.index) из \(rotation.total)...")
                    try? await Task.sleep(for: .milliseconds(500))
                } else {
                    let delay = max(3.0, (error.retryAfter ?? 10.0) + 1.0)
                    let delayFormatted = String(format: "%.1f", delay)
                    await onStatus?("Превышен лимит запросов Google API. Ожидание \(delayFormatted) сек перед повтором...")
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }
        throw lastError ?? GeminiAPIError(code: 429, status: "RESOURCE_EXHAUSTED", message: "Превышен лимит запросов к Gemini", retryAfter: 10)
    }

    private func performTranscribe(
        audioURL: URL,
        model: String,
        onStatus: (@Sendable (String) async -> Void)?
    ) async throws -> [TranscriptSegment] {
        let key = currentAPIKey()
        let mime = mimeType(for: audioURL)
        let fileSize = (try? audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let sizeMB = String(format: "%.1f МБ", Double(fileSize) / (1024 * 1024))
        await onStatus?("Загрузка аудио в Google Cloud (\(sizeMB))...")
        var uploaded = try await upload(audioURL, mimeType: mime, key: key)
        uploaded.uploadedWithKey = key
        do {
            await onStatus?("Подготовка файла на сервере...")
            try await waitUntilActive(uploaded, key: key)
            await onStatus?("Распознавание речи через \(model)...")
            let body = GeminiTranscriptionPayload.request(model: model, audio: [
                "type": "audio", "uri": uploaded.uri, "mime_type": uploaded.mimeType ?? mime
            ])
            let data = try await sendJSON(body, path: "v1beta/interactions", apiKeyOverride: key)
            let segments = try GeminiTranscriptionPayload.parse(data, model: model)
            await deleteUploadedFile(uploaded)
            return segments
        } catch {
            await deleteUploadedFile(uploaded)
            throw error
        }
    }

    private func waitUntilActive(_ uploaded: UploadedFile, key: String) async throws {
        var file = uploaded
        for _ in 0..<60 {
            try Task.checkCancellation()
            switch file.state {
            case "ACTIVE": return
            case "PROCESSING", "STATE_UNSPECIFIED", nil: break
            default:
                throw GeminiAPIError(code: -1, status: "UPLOAD", message: "Google не смог подготовить аудиофайл", retryAfter: nil)
            }
            try await Task.sleep(for: .seconds(2))
            var request = URLRequest(url: baseURL.appending(path: "v1beta/\(file.name)"))
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)
            file = try JSONDecoder().decode(UploadedFile.self, from: data)
            file.uploadedWithKey = key
        }
        throw URLError(.timedOut)
    }

    private func deleteUploadedFile(_ file: UploadedFile) async {
        let key = file.uploadedWithKey ?? currentAPIKey()
        var request = URLRequest(url: baseURL.appending(path: "v1beta/\(file.name)"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        _ = try? await session.data(for: request)
    }

    private func upload(_ fileURL: URL, mimeType: String, key: String) async throws -> UploadedFile {
        let bytes = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        var start = URLRequest(url: baseURL.appending(path: "upload/v1beta/files"))
        start.httpMethod = "POST"
        start.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        start.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        start.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        start.setValue(String(bytes.count), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        start.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        start.setValue("application/json", forHTTPHeaderField: "Content-Type")
        start.httpBody = try JSONSerialization.data(withJSONObject: ["file": ["display_name": fileURL.lastPathComponent]])
        let (startData, startResponse) = try await session.data(for: start)
        try validate(response: startResponse, data: startData)
        guard let http = startResponse as? HTTPURLResponse,
              let uploadValue = http.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: uploadValue) else {
            throw GeminiAPIError(code: -1, status: "UPLOAD", message: "Google не вернул URL загрузки", retryAfter: nil)
        }

        var finish = URLRequest(url: uploadURL)
        finish.httpMethod = "POST"
        finish.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        finish.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        finish.httpBody = bytes
        let (finishData, finishResponse) = try await session.data(for: finish)
        try validate(response: finishResponse, data: finishData)
        struct Envelope: Decodable { let file: UploadedFile }
        var file = try JSONDecoder().decode(Envelope.self, from: finishData).file
        file.uploadedWithKey = key
        return file
    }

    private func sendJSON(_ object: [String: Any], path: String, apiKeyOverride: String? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue(apiKeyOverride ?? currentAPIKey(), forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: object)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func validate(response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let parsed = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let error = parsed?["error"] as? [String: Any]
            let message = (error?["message"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            let status = (error?["status"] as? String) ?? "HTTP_\(http.statusCode)"
            let retry = parseRetryDelay(message)
            throw GeminiAPIError(code: http.statusCode, status: status, message: message, retryAfter: retry)
        }
    }

    private func extractText(_ data: Data) throws -> String {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = root?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        for part in parts ?? [] {
            if let text = part["text"] as? String { return text }
            if let transcription = part["audioTranscription"] as? [String: Any], let text = transcription["text"] as? String { return text }
        }
        throw GeminiAPIError(code: -1, status: "EMPTY", message: "Gemini вернул пустой ответ", retryAfter: nil)
    }

    private func parseRetryDelay(_ message: String) -> TimeInterval? {
        guard let match = message.range(of: #"retry in ([0-9.]+)s"#, options: .regularExpression) else { return nil }
        let fragment = String(message[match]).components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined()
        return Double(fragment)
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a": "audio/m4a"
        case "wav": "audio/wav"
        case "flac": "audio/flac"
        case "aac": "audio/aac"
        default: "audio/mpeg"
        }
    }

    private static func silentWAV(duration: Double, sampleRate: Int) -> Data {
        let samples = max(1, Int(duration * Double(sampleRate)))
        let dataSize = samples * 2
        var data = Data()
        func append<T>(_ value: T) {
            var little = value
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(Data("RIFF".utf8)); append(UInt32(36 + dataSize).littleEndian)
        data.append(Data("WAVEfmt ".utf8)); append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian); append(UInt16(1).littleEndian)
        append(UInt32(sampleRate).littleEndian); append(UInt32(sampleRate * 2).littleEndian)
        append(UInt16(2).littleEndian); append(UInt16(16).littleEndian)
        data.append(Data("data".utf8)); append(UInt32(dataSize).littleEndian)
        data.append(Data(repeating: 0, count: dataSize))
        return data
    }
}
