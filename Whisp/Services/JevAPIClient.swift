import Foundation

struct JevClassification: Sendable {
    let subject: String?
    let subjectConfidence: Double
    let educationalProbability: Double?
}

struct JevAPIError: Error, LocalizedError, Sendable {
    let code: Int
    let message: String

    var errorDescription: String? { message }
}

actor JevAPIClient {
    private let apiKey: String
    private let model: String
    private let endpoint: URL
    private let session: URLSession

    init(apiKey: String, configuration: JevConfiguration, proxy: ProxyConfiguration) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = URL(string: configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? URL(string: "https://openrouter.ai/api/alpha/decisions")!
        let proxyDelegate = ProxyTransport.authenticationDelegate(proxy: proxy)
        let sessionConfiguration = ProxyTransport.sessionConfiguration(proxy: proxy)
        sessionConfiguration.timeoutIntervalForRequest = 45
        sessionConfiguration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: sessionConfiguration, delegate: proxyDelegate, delegateQueue: nil)
    }

    func classify(transcript: String, subjects: [String], checkEducationalContent: Bool) async throws -> JevClassification {
        guard !apiKey.isEmpty else { throw JevAPIError(code: 401, message: "Для Jev не задан ключ OpenRouter") }
        guard !model.isEmpty else { throw JevAPIError(code: 400, message: "Для Jev не задана модель") }

        let normalizedSubjects = subjects.enumerated().map { index, subject in
            (key: "subject_\(index)", name: subject)
        }
        var criteria = Dictionary(uniqueKeysWithValues: normalizedSubjects.map { item in
            (item.key, "Учебный фрагмент по предмету «\(item.name)».")
        })
        criteria["unknown"] = "Учебного содержания нет или предмет невозможно определить по тексту."

        var questions: [String: [String: Any]] = [
            "subject": [
                "type": "choice",
                "instructions": "К какому предмету относится учебный фрагмент? Выбери наиболее точный вариант.",
                "criteria": criteria
            ]
        ]
        if checkEducationalContent {
            questions["educational"] = [
                "type": "noul",
                "instructions": "Содержит ли фрагмент проверяемое учебное содержание, а не бытовой разговор, приветствия или шум?"
            ]
        }

        let state = Self.compactTranscript(transcript)
        let body: [String: Any] = [
            "model": model,
            "state": state,
            "questions": questions
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JevAPIError(code: -1, message: "Jev вернул некорректный ответ")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(from: data) ?? "Jev вернул HTTP \(http.statusCode)"
            throw JevAPIError(code: http.statusCode, message: message)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = root["answers"] as? [String: Any],
              let subjectAnswer = answers["subject"] as? [String: Any] else {
            throw JevAPIError(code: -1, message: "Jev вернул ответ без классификации")
        }

        let choice = subjectAnswer["choice"] as? String
        let subject = normalizedSubjects.first(where: { $0.key == choice })?.name
        let subjectConfidence = (subjectAnswer["confidence"] as? NSNumber)?.doubleValue ?? 0
        var educationalProbability: Double?
        if let educational = answers["educational"] as? [String: Any] {
            educationalProbability = (educational["noul"] as? NSNumber)?.doubleValue
        }
        return JevClassification(
            subject: subject,
            subjectConfidence: subjectConfidence,
            educationalProbability: educationalProbability
        )
    }

    private static func compactTranscript(_ transcript: String) -> String {
        guard transcript.count > 42_000 else { return transcript }
        return String(transcript.prefix(28_000)) + "\n[…середина расшифровки опущена…]\n" + String(transcript.suffix(12_000))
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = root["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return root["message"] as? String
    }
}
