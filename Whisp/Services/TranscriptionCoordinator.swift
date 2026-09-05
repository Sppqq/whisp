import Foundation

actor TranscriptionCoordinator {
    struct Callbacks: Sendable {
        var onSegment: @Sendable (TranscriptSegment) -> Void
        var onFallbackOpened: @Sendable (FallbackInterval) -> Void
        var onFallbackClosed: @Sendable (TimeInterval) -> Void
        var onStatus: @Sendable (String) -> Void
        var onGeminiState: @Sendable (ServiceConnectionState) -> Void
        var onWhisperState: @Sendable (ServiceConnectionState) -> Void
    }

    private let apiKey: String
    private let proxy: ProxyConfiguration
    private let settings: WhispSettings
    private let whisper = WhisperFallbackService()
    private let elapsed: @Sendable () -> TimeInterval
    private let callbacks: Callbacks
    private var live: GeminiLiveClient?
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var rolloverTask: Task<Void, Never>?
    private var overlapBuffer: [Float] = []
    private let overlapSampleLimit = 16_000 * 5
    private var fallbackOpen = false
    private var retryAllowed = true
    private var lastFinalTime: TimeInterval = 0
    private var lastSystemVoiceAt: ContinuousClock.Instant?
    private var isPaused = false
    private var stopped = false

    init(
        apiKey: String,
        proxy: ProxyConfiguration,
        settings: WhispSettings,
        elapsed: @escaping @Sendable () -> TimeInterval,
        callbacks: Callbacks
    ) {
        self.apiKey = apiKey
        self.proxy = proxy
        self.settings = settings
        self.elapsed = elapsed
        self.callbacks = callbacks
    }

    func start() async {
        Task { [weak self] in await self?.prepareWhisper() }
        await connectLive(planned: false)
    }

    private func prepareWhisper() async {
        callbacks.onWhisperState(.checking)
        do {
            try await whisper.prepare()
            callbacks.onWhisperState(.local)
        } catch {
            callbacks.onWhisperState(.unavailable(error.localizedDescription))
            callbacks.onStatus("Whisper загружается: \(error.localizedDescription)")
        }
    }

    func append(samples: [Float], source: AudioSource) async {
        guard !stopped, !isPaused, !samples.isEmpty else { return }
        let now = elapsed()
        let energy = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        if source == .system, energy > 0.008 { lastSystemVoiceAt = .now }
        if source == .microphone, let lastSystemVoiceAt,
           lastSystemVoiceAt.duration(to: .now) < .milliseconds(600) { return }

        overlapBuffer.append(contentsOf: samples)
        if overlapBuffer.count > overlapSampleLimit {
            overlapBuffer.removeFirst(overlapBuffer.count - overlapSampleLimit)
        }

        // Keep local Whisper independent from the network path. Its inference
        // can take longer than an audio buffer and must never delay Gemini.
        Task { [weak self] in
            guard let self else { return }
            if let local = await self.whisper.append(samples: samples, at: now) {
                await self.receiveLocal(local)
            }
        }
        guard let live, !fallbackOpen else { return }
        do {
            try await live.sendPCM16(PCMNormalizer.pcm16Data(from: samples))
        } catch {
            openFallback(reason: classify(error), message: error.localizedDescription)
            scheduleReconnect()
        }
    }

    func pause() async {
        isPaused = true
        if let local = await whisper.flush(endTime: elapsed()), fallbackOpen { callbacks.onSegment(local) }
        overlapBuffer.removeAll(keepingCapacity: true)
        try? await live?.finishUtterance()
    }

    func resume() { isPaused = false }

    func stop() async {
        stopped = true
        reconnectTask?.cancel()
        rolloverTask?.cancel()
        eventTask?.cancel()
        if let local = await whisper.flush(endTime: elapsed()), fallbackOpen { callbacks.onSegment(local) }
        if fallbackOpen { callbacks.onFallbackClosed(elapsed()); fallbackOpen = false }
        await live?.disconnect()
        overlapBuffer.removeAll(keepingCapacity: false)
        live = nil
    }

    private func connectLive(planned: Bool) async {
        guard !stopped, !apiKey.isEmpty, retryAllowed else {
            if apiKey.isEmpty { openFallback(reason: .authentication, message: "Ключ Gemini не настроен") }
            return
        }
        callbacks.onGeminiState(.checking)
        let client = GeminiLiveClient(
            apiKey: apiKey,
            model: settings.geminiLiveModel,
            vocabulary: settings.customVocabulary,
            proxy: proxy
        )
        do {
            let events = try await client.connect()
            if !overlapBuffer.isEmpty {
                try await client.sendPCM16(PCMNormalizer.pcm16Data(from: overlapBuffer))
            }
            reconnectTask?.cancel()
            reconnectTask = nil
            await live?.disconnect()
            live = client
            if fallbackOpen {
                callbacks.onFallbackClosed(elapsed())
                fallbackOpen = false
            }
            callbacks.onGeminiState(.available)
            callbacks.onStatus(planned ? "Gemini Live: новая сессия" : "Gemini Live подключён")
            eventTask?.cancel()
            eventTask = Task { [weak self] in
                for await event in events { await self?.handle(event) }
            }
            scheduleRollover()
        } catch {
            let reason = classify(error)
            openFallback(reason: reason, message: error.localizedDescription)
            if reason != .quota { scheduleReconnect() }
        }
    }

    private func handle(_ event: GeminiLiveClient.Event) {
        switch event {
        case .interim:
            break
        case .final(let text):
            let now = elapsed()
            let start = max(lastFinalTime, now - max(0.5, Double(text.count) / 12))
            lastFinalTime = now
            callbacks.onSegment(TranscriptSegment(
                start: start,
                end: now,
                text: text,
                source: .geminiLive,
                model: settings.geminiLiveModel
            ))
        case .disconnected(let reason, let message):
            openFallback(reason: reason, message: message)
            if reason != .quota { scheduleReconnect() }
        }
    }

    private func openFallback(reason: FallbackReason, message: String) {
        guard !fallbackOpen, !stopped else { return }
        if reason == .quota { retryAllowed = false }
        fallbackOpen = true
        callbacks.onGeminiState(.unavailable(reason.title))
        callbacks.onFallbackOpened(FallbackInterval(start: elapsed(), reason: reason))
        callbacks.onStatus("Gemini недоступен — работает локальная модель: \(message)")
    }

    private func receiveLocal(_ segment: TranscriptSegment) {
        guard fallbackOpen, !stopped else { return }
        callbacks.onSegment(segment)
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil || reconnectTask?.isCancelled == true else { return }
        reconnectTask = Task { [weak self] in
            var delay: UInt64 = 2
            while let self, !Task.isCancelled, await self.shouldReconnect() {
                try? await Task.sleep(for: .seconds(delay))
                await self.connectLive(planned: false)
                delay = min(60, delay * 2)
            }
        }
    }

    private func scheduleRollover() {
        rolloverTask?.cancel()
        rolloverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(9 * 60))
            guard let self, !Task.isCancelled else { return }
            await self.connectLive(planned: true)
        }
    }

    private func classify(_ error: Error) -> FallbackReason {
        if let api = error as? GeminiAPIError { return api.fallbackReason }
        if let url = error as? URLError {
            if url.code == .timedOut { return .timeout }
            if url.code == .cannotConnectToHost || url.code == .cannotFindHost { return .proxy }
            return .network
        }
        return .websocket
    }

    private func shouldReconnect() -> Bool { !stopped && fallbackOpen && retryAllowed }
}
