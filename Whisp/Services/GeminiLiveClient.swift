import Foundation

actor GeminiLiveClient {
    enum Event: Sendable {
        case interim(String)
        case final(String)
        case disconnected(FallbackReason, String)
    }

    private let apiKey: String
    private let model: String
    private let vocabulary: [String]
    private let session: URLSession
    private let proxyDelegate: ProxyAuthenticationDelegate?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var continuation: AsyncStream<Event>.Continuation?

    init(apiKey: String, model: String, vocabulary: [String], proxy: ProxyConfiguration) {
        self.apiKey = apiKey
        self.model = model
        self.vocabulary = vocabulary
        let proxyDelegate = ProxyTransport.authenticationDelegate(proxy: proxy)
        self.proxyDelegate = proxyDelegate
        self.session = URLSession(
            configuration: ProxyTransport.sessionConfiguration(proxy: proxy),
            delegate: proxyDelegate,
            delegateQueue: nil
        )
    }

    func connect() async throws -> AsyncStream<Event> {
        guard var components = URLComponents(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent") else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw URLError(.badURL) }
        let socket = session.webSocketTask(with: url)
        self.socket = socket
        socket.resume()

        let pair = AsyncStream<Event>.makeStream()
        let stream = pair.stream
        self.continuation = pair.continuation
        let setup: [String: Any] = [
            "setup": [
                "model": "models/\(model)",
                "generationConfig": ["responseModalities": ["TEXT"]],
                "inputAudioTranscription": [
                    "languageCodes": ["ru-RU", "en-US"],
                    "customVocabulary": Array(vocabulary.prefix(100)),
                    "mode": "VERBATIM"
                ]
            ]
        ]
        try await send(setup)
        receiveTask = Task { [weak self] in await self?.receiveLoop() }
        return stream
    }

    func sendPCM16(_ data: Data) async throws {
        try await send([
            "realtimeInput": ["audio": ["data": data.base64EncodedString(), "mimeType": "audio/pcm;rate=16000"]]
        ])
    }

    func finishUtterance() async throws {
        try await send(["realtimeInput": ["audioStreamEnd": true]])
    }

    func disconnect() {
        receiveTask?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
        continuation?.finish()
        socket = nil
    }

    private func send(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8), let socket else { throw URLError(.notConnectedToInternet) }
        try await socket.send(.string(string))
    }

    private func receiveLoop() async {
        guard let socket else { return }
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .string(let string): data = Data(string.utf8)
                case .data(let value): data = value
                @unknown default: continue
                }
                parseEvent(data)
            }
        } catch {
            let reason: FallbackReason
            if let urlError = error as? URLError {
                reason = urlError.code == .timedOut ? .timeout : .network
            } else {
                reason = .websocket
            }
            continuation?.yield(.disconnected(reason, error.localizedDescription))
            continuation?.finish()
        }
    }

    private func parseEvent(_ data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let error = root["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? -1
            let status = error["status"] as? String ?? "LIVE"
            let message = error["message"] as? String ?? "Ошибка Gemini Live"
            let apiError = GeminiAPIError(code: code, status: status, message: message, retryAfter: nil)
            continuation?.yield(.disconnected(apiError.fallbackReason, message))
            return
        }
        let content = root["serverContent"] as? [String: Any] ?? root["server_content"] as? [String: Any]
        if let final = content?["inputTranscription"] as? [String: Any] ?? content?["input_transcription"] as? [String: Any],
           let text = final["text"] as? String, !text.isEmpty {
            continuation?.yield(.final(text))
        } else if let interim = content?["interimInputTranscription"] as? [String: Any] ?? content?["interim_input_transcription"] as? [String: Any],
                  let text = interim["text"] as? String, !text.isEmpty {
            continuation?.yield(.interim(text))
        }
    }
}
