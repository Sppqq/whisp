import AppKit
import AVFoundation
import CFNetwork
import Foundation
import Observation

struct ProcessingLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp = Date()
    let message: String

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

@MainActor
@Observable
final class AppModel {
    let settingsStore = SettingsStore()
    let audioCapture = AudioCaptureService()
    let player = AudioPlayerController()
    let updateService = UpdateService()

    var sessions: [LectureSession] = []
    var currentSession: LectureSession?
    var selectedSessionID: UUID?
    var statusMessage = "Готово к записи"
    var processingProgress = 0.0
    var processingLogs: [ProcessingLogEntry] = []
    var processingCurrentChunk = 0
    var processingTotalChunks = 0
    var processingChunkRange = ""
    var processingStartTime: Date?
    var showStopConfirmation = false
    var showSettings = false
    var recoverableSession: LectureSession?
    var showRecoveryPrompt = false
    var showBackfillPrompt = false
    var showBackfillComparison = false
    var backfillBefore = ""
    var backfillAfter = ""
    var lastError: String?
    var geminiState: ServiceConnectionState = .unchecked
    var whisperState: ServiceConnectionState = .unchecked
    var proxyState: ServiceConnectionState = .unchecked
    var webDAVState: ServiceConnectionState = .unchecked
    var inputDevices: [AudioInputDevice] = []
    var importedFileName: String?
    var pendingImportURLs: [URL] = []
    private(set) var isImportQueueActive = false
    var pendingImportFileNames: [String] { pendingImportURLs.map(\.lastPathComponent) }
    var needsScreenCapturePermission = false
    var needsMicrophonePermission = false
    private(set) var isWorking = false

    private let store = SessionStore.shared
    private let clock = RecordingClock()
    private let processor = AudioPostProcessor()
    private let hotKeys = HotKeyService()
    private var coordinator: TranscriptionCoordinator?
    private var backfillMonitor: Task<Void, Never>?
    private var syncRetryTask: Task<Void, Never>?
    private var currentMixURL: URL?
    private var processingTask: Task<Void, Never>?

    init() {
        audioCapture.onSamples = { [weak self] samples, source in
            Task { @MainActor [weak self] in
                guard let coordinator = self?.coordinator else { return }
                await coordinator.append(samples: samples, source: source)
            }
        }
        audioCapture.onChunk = { [weak self] chunk in
            self?.receive(chunk: chunk)
        }
        audioCapture.onError = { [weak self] message in
            self?.lastError = message
            self?.statusMessage = message
        }
        hotKeys.onRecordToggle = { [weak self] in self?.toggleRecordingFromHotKey() }
        hotKeys.onFinish = { [weak self] in
            guard self?.isRecording == true else { return }
            self?.showStopConfirmation = true
        }
        if !isRunningTests {
            hotKeys.install()
            applyHotkeys()
        }
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    var isRecording: Bool { currentSession.map { [.recording, .paused].contains($0.status) } ?? false }
    var isPaused: Bool { currentSession?.status == .paused }
    var isBatchRegenerating = false
    var batchTotalCount = 0
    var batchCurrentIndex = 0
    var batchCurrentTitle = ""
    var batchSuccessCount = 0
    var batchFailureCount = 0
    var showBatchRegenerateSheet = false
    var batchForceOverwrite = true
    var batchLogs: [ProcessingLogEntry] = []
    var isGeneratingQuiz = false
    var isRestoringFromWebDAV = false
    private var batchRegenerateTask: Task<Void, Never>?

    var isBusy: Bool { isRecording || isBatchRegenerating || isRestoringFromWebDAV }
    private(set) var activeProcessingSessionID: UUID?
    var selectedMicrophoneID: UInt32? {
        get { settingsStore.settings.preferredMicrophoneID }
        set { settingsStore.settings.preferredMicrophoneID = newValue }
    }
    var activeSubjects: [String] {
        settingsStore.settings.subjects.filter(\.isEnabled).sorted { $0.order < $1.order }.map(\.name)
    }
    var displayedSession: LectureSession? {
        if let currentSession { return currentSession }
        return sessions.first { $0.id == selectedSessionID }
    }

    func showStartScreen() {
        guard !isRecording else { return }
        resetSessionTasks()
        player.stop()
        currentSession = nil
        selectedSessionID = nil
        importedFileName = nil
        lastError = nil
        if activeProcessingSessionID == nil {
            processingProgress = 0
            statusMessage = "Готово к записи"
        }
    }

    func selectSession(_ id: UUID?) {
        guard !isRecording else { return }
        guard id != currentSession?.id else { return }
        resetSessionTasks()
        selectedSessionID = id
        guard let id else {
            currentSession = nil
            return
        }
        let selected = sessions.first { $0.id == id }
        if let selected, selected.id != activeProcessingSessionID, [.recording, .paused, .processing].contains(selected.status) {
            // An interrupted historical session is not an active audio capture.
            currentSession = nil
            recoverableSession = selected
            showRecoveryPrompt = true
            return
        }
        currentSession = selected
        importedFileName = currentSession?.importedAudioPath
        lastError = nil
        beginBackfillMonitorIfNeeded()
    }

    func deleteSession(_ id: UUID) {
        Task { @MainActor in
            if currentSession?.id == id {
                processingTask?.cancel()
                processingTask = nil
                showStartScreen()
            }
            try? await store.delete(id)
            sessions = (try? await store.loadAll()) ?? []
        }
    }

    private func resetSessionTasks() {
        backfillMonitor?.cancel()
        backfillMonitor = nil
        syncRetryTask?.cancel()
        syncRetryTask = nil
        currentMixURL = nil
        player.stop()
        showBackfillPrompt = false
    }

    func openScreenCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    func launch() async {
        guard !isRunningTests else { return }
        showSettings = settingsStore.activeProviderAPIKeys.isEmpty || settingsStore.activeProviderEndpoint == nil
        refreshInputDevices()
        do {
            sessions = try await store.loadAll()
            if let uploading = sessions.first(where: { $0.status == .uploading }) {
                currentSession = uploading
                selectedSessionID = uploading.id
                await syncCurrent()
            }
            let recoverable = try await store.recoverableSessions()
            recoverableSession = recoverable.first { $0.status != .uploading }
            showRecoveryPrompt = recoverableSession != nil
            if currentSession == nil, recoverableSession == nil, let pending = sessions.first(where: \.hasPendingBackfill) {
                currentSession = pending
                selectedSessionID = pending.id
                beginBackfillMonitorIfNeeded()
            }
            try await store.removeExpiredSessions(retentionDays: settingsStore.settings.localRetentionDays)
        } catch { lastError = error.localizedDescription }
        if updateService.automaticallyChecksForUpdates {
            Task { [updateService] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await updateService.checkForUpdates(silent: true)
            }
        }
    }

    func startRecording(captureSystemAudio: Bool = true) async {
        guard !isBusy else { return }
        resetSessionTasks()
        needsScreenCapturePermission = false
        needsMicrophonePermission = false
        var session = LectureSession()
        session.startedAt = Date()
        session.title = WhispFormatting.datedTitle(title: "Новая лекция", date: session.startedAt ?? Date())
        session.status = .recording
        session.captureSystemAudio = captureSystemAudio
        currentSession = session
        selectedSessionID = session.id
        clock.start(at: session.startedAt ?? Date())
        do {
            let directory = try await store.directory(for: session.id)
            let coordinator = makeCoordinator()
            self.coordinator = coordinator
            try await audioCapture.start(
                directory: directory,
                systemAudio: captureSystemAudio,
                microphoneID: selectedMicrophoneID
            )
            statusMessage = "Запись идёт"
            try await persistCurrent()
            Task { await coordinator.start() }
        } catch {
            await audioCapture.stop()
            await coordinator?.stop()
            coordinator = nil
            currentSession?.status = .failed
            currentSession?.lastError = error.localizedDescription
            if let captureError = error as? AudioCaptureService.CaptureError {
                switch captureError {
                case .screenCaptureDenied: needsScreenCapturePermission = true
                case .microphoneDenied: needsMicrophonePermission = true
                default: break
                }
            }
            lastError = error.localizedDescription
            statusMessage = "Не удалось начать запись"
            try? await persistCurrent()
        }
    }

    func cancelProcessing() async {
        pendingImportURLs.removeAll()
        addProcessingLog("Запрос на отмену обработки...")
        statusMessage = "Отменяем обработку..."
        processingTask?.cancel()
        processingTask = nil
        isWorking = false

        guard var session = currentSession else { return }
        if session.status == .processing {
            session.status = (session.finalTranscript.isEmpty && session.rawTranscript.isEmpty) ? .draft : .review
            session.lastError = "Обработка отменена пользователем"
            currentSession = session
            lastError = nil
            statusMessage = "Обработка отменена"
            addProcessingLog("Обработка остановлена по запросу пользователя.")
            try? await persistCurrent()
        }
    }

    func enqueueAudioImports(_ sourceURLs: [URL]) {
        guard !isRecording, !isBatchRegenerating, !isRestoringFromWebDAV else {
            lastError = "Завершите текущую задачу перед импортом файлов"
            return
        }

        let existingPaths = Set(pendingImportURLs.map(\.standardizedFileURL.path))
        let unique = sourceURLs.filter { url in
            url.isFileURL && !existingPaths.contains(url.standardizedFileURL.path)
        }
        guard !unique.isEmpty else { return }
        pendingImportURLs.append(contentsOf: unique)
        statusMessage = unique.count == 1
            ? "Файл добавлен в очередь"
            : "В очередь добавлено " + String(unique.count) + " файлов"

        guard !isImportQueueActive else { return }
        isImportQueueActive = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isImportQueueActive = false }
            while !self.pendingImportURLs.isEmpty, !Task.isCancelled {
                let next = self.pendingImportURLs.removeFirst()
                await self.importAudio(from: next)
            }
        }
    }

    func cancelImportQueue() {
        pendingImportURLs.removeAll()
        Task { await cancelProcessing() }
    }

    var geminiDiagnostics: String {
        let keys = settingsStore.geminiAPIKeys
        guard !keys.isEmpty else { return "Gemini: ключ не добавлен" }
        let statuses = keys.map { settingsStore.status(for: $0) }
        let valid = statuses.filter { if case .valid = $0 { return true }; return false }.count
        let quota = statuses.filter { if case .quotaExceeded = $0 { return true }; return false }.count
        if valid > 0 { return "Gemini: доступен " + String(valid) + " из " + String(keys.count) + " ключей" }
        if quota > 0 { return "Gemini: лимит у " + String(quota) + " из " + String(keys.count) + " ключей" }
        return "Gemini: " + String(keys.count) + " ключ(а), подключение не проверено"
    }

    func retryFailedStage() async {
        guard let session = currentSession, session.status == .failed else { return }
        if !session.finalTranscript.isEmpty || !session.rawTranscript.isEmpty {
            isWorking = true
            defer { isWorking = false }
            lastError = nil
            currentSession?.lastError = nil
            currentSession?.status = .processing
            processingProgress = 0.72
            clearProcessingLogs()
            addProcessingLog("Повторный запуск генерации конспекта без новой расшифровки...")
            try? await persistCurrent()
            await regenerateAnalysis(for: session.id)
        } else {
            await retryProcessing()
        }
    }
    func importAudio(from sourceURL: URL) async {
        guard !isBusy else { return }
        isWorking = true
        defer { isWorking = false }
        processingTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            await self.executeImportAudio(from: sourceURL)
        }
        processingTask = task
        await task.value
    }

    private func executeImportAudio(from sourceURL: URL) async {
        resetSessionTasks()
        lastError = nil
        let accessed = sourceURL.startAccessingSecurityScopedResource()

        var session = LectureSession()
        session.startedAt = Date()
        session.status = .processing
        session.captureSystemAudio = false
        session.title = WhispFormatting.datedTitle(title: sourceURL.deletingPathExtension().lastPathComponent, date: session.startedAt ?? Date())
        currentSession = session
        selectedSessionID = session.id
        importedFileName = sourceURL.lastPathComponent
        activeProcessingSessionID = session.id
        processingProgress = 0.02
        statusMessage = "Импортируем \(sourceURL.lastPathComponent)"
        clearProcessingLogs()
        addProcessingLog("Импорт файла: \(sourceURL.lastPathComponent)")

        defer {
            activeProcessingSessionID = nil
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        do {
            let directory = try await store.directory(for: session.id)
            let preservedName = "Исходник-\(WhispFormatting.safePathComponent(sourceURL.lastPathComponent))"
            let preservedURL = directory.appending(path: preservedName)
            addProcessingLog("Копирование исходного аудио в рабочую папку...")
            try await Task.detached(priority: .userInitiated) {
                if FileManager.default.fileExists(atPath: preservedURL.path) {
                    try FileManager.default.removeItem(at: preservedURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: preservedURL)
            }.value

            session.importedAudioPath = preservedName
            if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
            else { sessions.insert(session, at: 0) }
            if currentSession?.id == session.id { currentSession = session }
            try await store.save(session)

            try Task.checkCancellation()

            statusMessage = "Подготавливаем аудиодорожку..."
            processingProgress = 0.05
            addProcessingLog("Подготовка аудиофайла...")
            let microphone = try await processor.prepareImportedAudio(source: preservedURL, directory: directory)
            currentMixURL = microphone
            player.load(microphone)
            let asset = AVURLAsset(url: microphone)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw AudioPostProcessor.ProcessingError.noAudio }
            session.endedAt = session.startedAt?.addingTimeInterval(duration)
            if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
            if currentSession?.id == session.id { currentSession = session }
            try await store.save(session)

            try Task.checkCancellation()

            let durationDesc = WhispFormatting.durationDescription(duration)
            addProcessingLog("Аудио готово: \(WhispFormatting.timestamp(duration)) (\(durationDesc)).")

            guard !settingsStore.activeProviderAPIKeys.isEmpty else {
                addProcessingLog("Ошибка: не указан API key активного провайдера")
                throw GeminiAPIError(code: 401, status: "API_KEY", message: "Сначала добавьте API key активного провайдера в Настройках", retryAfter: nil)
            }

            statusMessage = "Расшифровываем импортированную запись"
            addProcessingLog("Запуск расшифровки через \(settingsStore.activeProviderName), модель \(settingsStore.activeTranscriptionModel)...")
            let service = FinalTranscriptionService(
                client: try providerClient(),
                processor: processor,
                model: settingsStore.activeTranscriptionModel,
                providerName: settingsStore.activeProviderName,
                vocabulary: settingsStore.settings.customVocabulary,
                onProgress: progressHandler(sessionID: session.id)
            )
            let transcript = try await service.transcribe(mixURL: microphone, directory: directory)

            try Task.checkCancellation()

            if let index = sessions.firstIndex(where: { $0.id == session.id }) { session = sessions[index] }
            session.rawTranscript = transcript
            session.finalTranscript = transcript
            if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
            if currentSession?.id == session.id { currentSession = session }
            try await store.save(session)

            processingProgress = 0.82
            statusMessage = "Создаём конспект"
            addProcessingLog("Расшифровка завершена (всего \(transcript.count) сегментов). Генерация конспекта...")
            await regenerateAnalysis(for: session.id)
            addProcessingLog("Лекция успешно собрана!")
            processingProgress = 1.0
        } catch is CancellationError {
            let updatedStatus: LectureStatus = (session.finalTranscript.isEmpty && session.rawTranscript.isEmpty) ? .draft : .review
            session.status = updatedStatus
            session.lastError = "Обработка отменена пользователем"
            if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
            if currentSession?.id == session.id { currentSession = session }
            lastError = nil
            statusMessage = "Обработка отменена"
            addProcessingLog("Обработка остановлена пользователем.")
            try? await store.save(session)
        } catch {
            if Task.isCancelled {
                let updatedStatus: LectureStatus = (session.finalTranscript.isEmpty && session.rawTranscript.isEmpty) ? .draft : .review
                session.status = updatedStatus
                session.lastError = "Обработка отменена пользователем"
                if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
                if currentSession?.id == session.id { currentSession = session }
                lastError = nil
                statusMessage = "Обработка отменена"
                addProcessingLog("Обработка остановлена пользователем.")
                try? await store.save(session)
            } else {
                session.status = .failed
                session.lastError = error.localizedDescription
                if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
                if currentSession?.id == session.id { currentSession = session }
                lastError = error.localizedDescription
                statusMessage = "Не удалось обработать импорт: \(error.localizedDescription)"
                addProcessingLog("Ошибка обработки: \(error.localizedDescription)")
                try? await store.save(session)
            }
        }
    }

    func pauseOrResume() async {
        guard var session = currentSession else { return }
        if session.status == .recording {
            session.status = .paused
            session.pauses.append(PauseInterval(start: Date()))
            currentSession = session
            clock.pause()
            audioCapture.pause()
            await coordinator?.pause()
            statusMessage = "Пауза"
        } else if session.status == .paused {
            if let index = session.pauses.indices.last { session.pauses[index].end = Date() }
            session.status = .recording
            currentSession = session
            clock.resume()
            do { try audioCapture.resume(); await coordinator?.resume(); statusMessage = "Запись продолжается" }
            catch { lastError = error.localizedDescription }
        }
        try? await persistCurrent()
    }

    func confirmStop() async {
        showStopConfirmation = false
        guard !isWorking, isRecording, var session = currentSession else { return }
        isWorking = true
        defer { isWorking = false }
        if session.status == .paused, let index = session.pauses.indices.last { session.pauses[index].end = Date() }
        session.endedAt = Date()
        session.status = .processing
        currentSession = session
        statusMessage = "Сохраняем аудио"
        await audioCapture.stop()
        await coordinator?.stop()
        coordinator = nil
        session = currentSession ?? session
        if let index = session.fallbackIntervals.lastIndex(where: \.isOpen) {
            session.fallbackIntervals[index].end = clock.elapsed()
            session.fallbackIntervals[index].status = .pending
            currentSession = session
        }
        try? await persistCurrent()
        clearProcessingLogs()
        addProcessingLog("Запись завершена. Запуск постобработки...")
        processingTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.processCurrentSession()
        }
        processingTask = task
        await task.value
    }

    func discardStopRequest() { showStopConfirmation = false }

    func recoverSession() async {
        showRecoveryPrompt = false
        guard !isBusy, var session = recoverableSession else { return }
        isWorking = true
        defer { isWorking = false }
        resetSessionTasks()
        session.endedAt = session.endedAt ?? Date()
        session.status = .processing
        currentSession = session
        selectedSessionID = session.id
        clearProcessingLogs()
        addProcessingLog("Восстановление сессии...")
        try? await persistCurrent()
        processingTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.processCurrentSession()
        }
        processingTask = task
        await task.value
    }

    func dismissRecovery() { showRecoveryPrompt = false }

    func retryProcessing() async {
        guard !isBusy, currentSession?.status == .failed || currentSession?.status == .draft else { return }
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        currentSession?.lastError = nil
        currentSession?.status = .processing
        processingProgress = 0
        clearProcessingLogs()
        addProcessingLog("Повторный запуск обработки...")
        try? await persistCurrent()
        processingTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.processCurrentSession()
        }
        processingTask = task
        await task.value
    }

    func updateReview(title: String? = nil, subject: String? = nil, raw: String? = nil, final: String? = nil, notes: String? = nil, studentNotes: String? = nil, quiz: String? = nil) {
        guard var session = currentSession else { return }
        if let title { session.title = title }
        if let subject { session.subject = subject }
        if let raw { session.rawMarkdown = raw }
        if let final { session.finalMarkdown = final; session.userEditedFinal = true }
        if let notes { session.notesMarkdown = notes; session.userEditedNotes = true }
        if let studentNotes { session.studentNotesMarkdown = studentNotes; session.userEditedStudentNotes = true }
        if let quiz { session.quizMarkdown = quiz }
        currentSession = session
        Task { try? await persistCurrent() }
    }

    func syncCurrent() async {
        guard !isBusy, var session = currentSession else { return }
        isWorking = true
        defer { isWorking = false }
        guard !settingsStore.webDAV.baseURL.isEmpty else { lastError = "Настройте WebDAV"; return }
        guard session.subject != "Не определено" else { lastError = "Выберите предмет"; return }
        session.status = .uploading
        currentSession = session
        statusMessage = "Загрузка в WebDAV"
        webDAVState = .checking
        do {
            let directory = try await store.directory(for: session.id)
            let client = WebDAVClient(configuration: settingsStore.webDAV)
            session.remotePath = try await client.upload(session: session, localDirectory: directory)
            session.status = .synced
            session.syncedAt = Date()
            currentSession = session
            statusMessage = "Синхронизировано"
            webDAVState = .available
            syncRetryTask?.cancel()
            syncRetryTask = nil
            try await persistCurrent()
        } catch {
            session.status = .uploading
            session.lastError = error.localizedDescription
            currentSession = session
            lastError = error.localizedDescription
            statusMessage = "Ошибка WebDAV"
            webDAVState = .unavailable(error.localizedDescription)
            try? await persistCurrent()
            scheduleSyncRetry()
        }
    }

    func reloadSessions() async {
        sessions = (try? await store.loadAll()) ?? []
        if currentSession == nil, let first = sessions.first {
            selectSession(first.id)
        }
    }

    func restoreFromWebDAV() async {
        guard !isBusy else { return }
        guard !settingsStore.webDAV.baseURL.isEmpty else {
            lastError = "Настройте адрес WebDAV в параметрах приложения"
            return
        }
        isRestoringFromWebDAV = true
        isWorking = true
        defer {
            isRestoringFromWebDAV = false
            isWorking = false
        }
        statusMessage = "Подключение к WebDAV..."
        webDAVState = .checking
        do {
            let client = WebDAVClient(configuration: settingsStore.webDAV)
            let count = try await client.restoreFromWebDAV(to: store) { [weak self] msg in
                Task { @MainActor in
                    self?.statusMessage = msg
                }
            }
            await reloadSessions()
            webDAVState = .available
            if count > 0 {
                statusMessage = "Загружено из WebDAV: \(count) лекций"
            } else {
                statusMessage = "Все лекции с WebDAV уже загружены на этот Mac"
            }
        } catch {
            webDAVState = .unavailable(error.localizedDescription)
            lastError = "Ошибка WebDAV: \(error.localizedDescription)"
            statusMessage = "Ошибка WebDAV: \(error.localizedDescription)"
        }
    }

    func loadPlayback(source: AudioSource) async {
        guard let session = currentSession ?? displayedSession else { return }
        do {
            let directory = try await store.directory(for: session.id)
            let name = source == .microphone ? "Микрофон.m4a" : "Системный звук.m4a"
            let url = directory.appending(path: name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                lastError = "Дорожка «\(name)» ещё не создана"
                return
            }
            player.load(url)
        } catch { lastError = error.localizedDescription }
    }

    func backfillNow() async {
        showBackfillPrompt = false
        guard !isBusy, var session = currentSession, session.hasPendingBackfill else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let directory = try await store.directory(for: session.id)
            let mix = try await ensureMix(session: session, directory: directory)
            let client = try providerClient()
            let service = BackfillService(client: client, model: settingsStore.activeTranscriptionModel, vocabulary: settingsStore.settings.customVocabulary, processor: processor)
            backfillBefore = session.finalMarkdown
            for index in session.fallbackIntervals.indices where ![.accepted, .declined].contains(session.fallbackIntervals[index].status) {
                session.fallbackIntervals[index].status = .processing
                currentSession = session
                let candidate = try await service.backfill(
                    session: session,
                    interval: session.fallbackIntervals[index],
                    mixURL: mix,
                    directory: directory
                )
                session.fallbackIntervals[index].candidateSegments = candidate
                session.fallbackIntervals[index].status = .needsReview
            }
            var candidateSession = session
            for interval in session.fallbackIntervals where interval.status == .needsReview {
                candidateSession.finalTranscript = TranscriptMerger.applyBackfill(
                    to: candidateSession.finalTranscript,
                    interval: interval,
                    replacements: interval.candidateSegments
                )
            }
            backfillAfter = MarkdownExporter.render(session: candidateSession).final
            currentSession = session
            showBackfillComparison = true
            try await persistCurrent()
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Дорасшифровка отложена"
        }
    }

    func acceptBackfill() async {
        showBackfillComparison = false
        guard var session = currentSession else { return }
        for index in session.fallbackIntervals.indices where session.fallbackIntervals[index].status == .needsReview {
            let interval = session.fallbackIntervals[index]
            session.finalTranscript = TranscriptMerger.applyBackfill(
                to: session.finalTranscript,
                interval: interval,
                replacements: interval.candidateSegments
            )
            session.fallbackIntervals[index].status = .accepted
        }
        session.userEditedFinal = false
        session.status = .processing
        currentSession = session
        await regenerateAnalysis()
    }

    func deferBackfill() {
        showBackfillPrompt = false
        guard var session = currentSession else { return }
        for index in session.fallbackIntervals.indices where session.fallbackIntervals[index].status == .available {
            session.fallbackIntervals[index].status = .deferred
            session.fallbackIntervals[index].retryAfter = Date().addingTimeInterval(3_600)
        }
        currentSession = session
        Task { try? await persistCurrent() }
    }

    func declineBackfill() {
        showBackfillPrompt = false
        guard var session = currentSession else { return }
        for index in session.fallbackIntervals.indices where ![.accepted, .declined].contains(session.fallbackIntervals[index].status) {
            session.fallbackIntervals[index].status = .declined
        }
        session.status = .review
        currentSession = session
        Task { try? await persistCurrent() }
    }

    func testGemini() async -> String {
        return await testActiveProvider()
    }

    func testActiveProvider() async -> String {
        geminiState = .checking
        proxyState = settingsStore.proxy.isEnabled ? .checking : .disabled
        do {
            try await providerClient().probeTranscription(settingsStore.activeTranscriptionModel)
            geminiState = .available
            let count = settingsStore.activeProviderAPIKeys.count
            let name = settingsStore.activeProviderName
            return count > 1 ? "\(name) доступен (\(count) ключей)" : "\(name) доступен"
        } catch {
            let message = connectionMessage(for: error)
            geminiState = .unavailable(message)
            proxyState = settingsStore.proxy.isEnabled ? .unavailable(message) : .disabled
            return message
        }
    }

    func testSingleGeminiKey(_ key: String) async -> GeminiKeyStatus {
        settingsStore.setKeyStatus(.checking, for: key)
        let client = geminiClient()
        do {
            try await client.probeKey(key, model: settingsStore.settings.geminiModel)
            let status = GeminiKeyStatus.valid
            settingsStore.setKeyStatus(status, for: key)
            return status
        } catch let error as GeminiAPIError where error.isRateLimitOrQuota {
            let status = GeminiKeyStatus.quotaExceeded(message: error.message)
            settingsStore.setKeyStatus(status, for: key)
            return status
        } catch {
            let status = GeminiKeyStatus.invalid(message: error.localizedDescription)
            settingsStore.setKeyStatus(status, for: key)
            return status
        }
    }

    func testAllGeminiKeys() async -> String {
        let keys = settingsStore.geminiAPIKeys
        guard !keys.isEmpty else { return "Нет ключей для проверки" }
        for key in keys {
            settingsStore.setKeyStatus(.checking, for: key)
        }
        var validCount = 0
        var quotaCount = 0
        var errorCount = 0
        for key in keys {
            let res = await testSingleGeminiKey(key)
            switch res {
            case .valid: validCount += 1
            case .quotaExceeded: quotaCount += 1
            case .invalid: errorCount += 1
            case .checking, .unchecked: break
            }
        }
        if validCount == keys.count {
            return "Все \(keys.count) ключей работают"
        }
        var summary = "Работают: \(validCount) из \(keys.count)"
        if quotaCount > 0 { summary += ", квота: \(quotaCount)" }
        if errorCount > 0 { summary += ", ошибки: \(errorCount)" }
        return summary
    }

    func testWebDAV() async -> String {
        webDAVState = .checking
        do {
            try await WebDAVClient(configuration: settingsStore.webDAV).checkConnection()
            webDAVState = .available
            return "WebDAV доступен"
        } catch {
            webDAVState = .unavailable(error.localizedDescription)
            return error.localizedDescription
        }
    }

    func refreshInputDevices() {
        audioCapture.refreshInputDevices()
        inputDevices = audioCapture.inputDevices
        if let selectedMicrophoneID,
           !inputDevices.contains(where: { $0.id == selectedMicrophoneID }) {
            self.selectedMicrophoneID = nil
        }
    }

    private func connectionMessage(for error: Error) -> String {
        let nsError = error as NSError
        if settingsStore.proxy.isEnabled,
           (nsError.domain == (kCFErrorDomainCFNetwork as String) || nsError.domain == NSURLErrorDomain) {
            switch nsError.code {
            case 310, -1000, -1001, -1003, -1004, -1005, -1200, -2096:
                return "Прокси не установил соединение. Проверьте его тип, адрес, порт и срок действия."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    func applyHotkeys() {
        hotKeys.configure(record: settingsStore.settings.hotkeyRecord, finish: settingsStore.settings.hotkeyFinish)
    }

    private func processCurrentSession() async {
        guard var session = currentSession else { return }
        activeProcessingSessionID = session.id
        defer { activeProcessingSessionID = nil }

        do {
            let directory = try await store.directory(for: session.id)
            let mix = try await ensureMix(session: session, directory: directory)
            player.load(directory.appending(path: "Микрофон.m4a"))
            if session.audioChunks.isEmpty {
                let duration = try await AVURLAsset(url: mix).load(.duration).seconds
                guard duration.isFinite, duration > 0 else { throw AudioPostProcessor.ProcessingError.noAudio }
                session.startedAt = session.startedAt ?? session.createdAt
                session.endedAt = session.startedAt?.addingTimeInterval(duration)
                if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
                if currentSession?.id == session.id { currentSession = session }
                try await store.save(session)
            }
            processingProgress = 0.25

            if !settingsStore.activeProviderAPIKeys.isEmpty {
                do {
                    statusMessage = "Финальная расшифровка: \(settingsStore.activeProviderName)"
                    let finalService = FinalTranscriptionService(
                        client: try providerClient(), processor: processor,
                        model: settingsStore.activeTranscriptionModel,
                        providerName: settingsStore.activeProviderName,
                        vocabulary: settingsStore.settings.customVocabulary,
                        onProgress: progressHandler(sessionID: session.id)
                    )
                    session.finalTranscript = try await finalService.transcribe(mixURL: mix, directory: directory)
                    if session.audioChunks.isEmpty { session.rawTranscript = session.finalTranscript }
                    session.lastError = nil
                    for index in session.fallbackIntervals.indices { session.fallbackIntervals[index].status = .accepted }
                } catch {
                    if session.audioChunks.isEmpty || session.rawTranscript.isEmpty { throw error }
                    session.finalTranscript = TranscriptMerger.merge(session.rawTranscript)
                    session.lastError = error.localizedDescription
                }
            } else {
                if session.rawTranscript.isEmpty {
                    throw GeminiAPIError(code: 401, status: "API_KEY", message: "Сначала добавьте API key активного провайдера", retryAfter: nil)
                }
                session.finalTranscript = TranscriptMerger.merge(session.rawTranscript)
            }
            processingProgress = 0.7
            if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
            if currentSession?.id == session.id { currentSession = session }
            try await store.save(session)
            await regenerateAnalysis(for: session.id)
        } catch is CancellationError {
            let updatedStatus: LectureStatus = (session.finalTranscript.isEmpty && session.rawTranscript.isEmpty) ? .draft : .review
            session.status = updatedStatus
            session.lastError = "Обработка отменена пользователем"
            if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
            if currentSession?.id == session.id { currentSession = session }
            lastError = nil
            statusMessage = "Обработка отменена"
            addProcessingLog("Обработка остановлена по запросу пользователя.")
            try? await store.save(session)
        } catch {
            if Task.isCancelled {
                let updatedStatus: LectureStatus = (session.finalTranscript.isEmpty && session.rawTranscript.isEmpty) ? .draft : .review
                session.status = updatedStatus
                session.lastError = "Обработка отменена пользователем"
                if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
                if currentSession?.id == session.id { currentSession = session }
                lastError = nil
                statusMessage = "Обработка отменена"
                addProcessingLog("Обработка остановлена по запросу пользователя.")
                try? await store.save(session)
            } else {
                session.status = .failed
                session.lastError = error.localizedDescription
                if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
                if currentSession?.id == session.id { currentSession = session }
                lastError = error.localizedDescription
                try? await store.save(session)
            }
        }
    }

    func regenerateAnalysis(for sessionID: UUID? = nil, forceOverwriteNotes: Bool = true) async {
        let targetID = sessionID ?? currentSession?.id
        guard let targetID, let index = sessions.firstIndex(where: { $0.id == targetID }) else { return }
        var session = sessions[index]
        if session.finalTranscript.isEmpty && !session.rawTranscript.isEmpty {
            session.finalTranscript = session.rawTranscript
        }
        var analysisError: String?
        if !settingsStore.activeProviderAPIKeys.isEmpty, !session.finalTranscript.isEmpty {
            do {
                statusMessage = "Создаём конспект через \(settingsStore.activeProviderName)..."
                let analysis = try await LectureAnalysisService(client: try providerClient(), model: settingsStore.activeAnalysisModel)
                    .analyze(segments: session.finalTranscript, subjects: activeSubjects, onStatus: { [weak self] status in
                        await MainActor.run { self?.statusMessage = status }
                    })
                session.analysis = analysis
                session.title = WhispFormatting.datedTitle(title: analysis.title, date: session.startedAt ?? session.createdAt)
                session.subject = analysis.confidence >= 0.65 ? analysis.subject : "Не определено"
                session.lastError = nil
                if forceOverwriteNotes {
                    session.userEditedNotes = false
                    session.userEditedStudentNotes = false
                }
            } catch {
                analysisError = error.localizedDescription
                session.lastError = error.localizedDescription
            }
        }
        session.status = session.hasPendingBackfill ? .awaitingBackfill : .review
        let previousNotes = session.notesMarkdown
        let previousStudentNotes = session.studentNotesMarkdown
        let previousFinal = session.finalMarkdown
        let preserveEditedNotes = session.userEditedNotes && !forceOverwriteNotes
        let preserveEditedStudentNotes = session.userEditedStudentNotes && !forceOverwriteNotes
        let rendered = MarkdownExporter.render(session: session)
        session.rawMarkdown = rendered.raw
        session.finalMarkdown = session.userEditedFinal ? previousFinal : rendered.final
        session.notesMarkdown = preserveEditedNotes ? previousNotes : rendered.notes
        session.studentNotesMarkdown = preserveEditedStudentNotes ? previousStudentNotes : rendered.studentNotebook
        sessions[index] = session
        try? await store.save(session)
        if currentSession?.id == targetID {
            currentSession = session
        }
        processingProgress = 1
        if let analysisError {
            statusMessage = "Расшифровка сохранена, но конспект не создан: \(analysisError)"
        } else {
            statusMessage = "Конспект обновлён"
        }
        beginBackfillMonitorIfNeeded()
    }

    func addBatchLog(_ message: String) {
        batchLogs.append(ProcessingLogEntry(message: message))
        if batchLogs.count > 120 {
            batchLogs.removeFirst(batchLogs.count - 120)
        }
    }

    func startBatchRegeneration(forceOverwrite: Bool) {
        guard !isBusy else { return }
        let eligible = sessions.filter { !$0.finalTranscript.isEmpty || !$0.rawTranscript.isEmpty }
        guard !eligible.isEmpty else {
            statusMessage = "Нет доступных лекций с расшифровкой"
            return
        }

        isBatchRegenerating = true
        batchTotalCount = eligible.count
        batchCurrentIndex = 0
        batchCurrentTitle = ""
        batchSuccessCount = 0
        batchFailureCount = 0
        batchLogs.removeAll()
        addBatchLog("🚀 Старт массовой перегенерации (\(eligible.count) лекций, модель: \(settingsStore.activeAnalysisModel))")

        batchRegenerateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for (idx, session) in eligible.enumerated() {
                if Task.isCancelled { break }
                self.batchCurrentIndex = idx + 1
                self.batchCurrentTitle = session.title
                self.statusMessage = "[\(idx + 1)/\(eligible.count)] Перегенерация: \(session.title)..."
                self.addBatchLog("[\(idx + 1)/\(eligible.count)] Анализируем: «\(session.title)»...")

                await self.regenerateAnalysis(for: session.id, forceOverwriteNotes: forceOverwrite)

                if let updated = self.sessions.first(where: { $0.id == session.id }) {
                    if updated.analysis != nil && updated.lastError == nil {
                        self.batchSuccessCount += 1
                        self.addBatchLog("✅ Готово: «\(updated.title)» (\(updated.subject))")
                    } else {
                        self.batchFailureCount += 1
                        let err = updated.lastError ?? "Неизвестная ошибка"
                        self.addBatchLog("⚠️ Ошибка «\(session.title)»: \(err)")
                    }
                }

                // Rate limiting pause between requests to prevent API throttling
                if idx < eligible.count - 1 {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                }
            }

            self.isBatchRegenerating = false
            self.statusMessage = "Массовая перегенерация завершена: успешно \(self.batchSuccessCount), ошибок \(self.batchFailureCount)"
            self.addBatchLog("🏁 Готово! Успешно: \(self.batchSuccessCount), Ошибок: \(self.batchFailureCount)")
            self.batchRegenerateTask = nil
        }
    }

    func cancelBatchRegeneration() {
        batchRegenerateTask?.cancel()
        batchRegenerateTask = nil
        isBatchRegenerating = false
        statusMessage = "Массовая перегенерация остановлена"
        addBatchLog("⏹️ Перегенерация прервана пользователем")
    }

    func revealInFinder(sessionID: UUID? = nil) {
        let targetID = sessionID ?? currentSession?.id ?? selectedSessionID
        Task { @MainActor in
            do {
                if let targetID {
                    let dir = try await store.directory(for: targetID)
                    NSWorkspace.shared.open(dir)
                } else {
                    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    let sessionsDir = appSupport.appending(path: "Whisp/Sessions", directoryHint: .isDirectory)
                    NSWorkspace.shared.open(sessionsDir)
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func openInObsidian(session: LectureSession? = nil) {
        let target = session ?? currentSession ?? displayedSession
        guard let target else { return }
        let lessonName = WhispFormatting.safePathComponent(target.title)
        if let encoded = lessonName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "obsidian://open?file=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    func exportMarkdownFile(session: LectureSession? = nil, tabName: String = "student", customContent: String? = nil) {
        let target = session ?? currentSession ?? displayedSession
        guard let target else { return }
        let panel = NSSavePanel()
        panel.title = "Экспорт заметки"
        let suffix: String
        let defaultContent: String
        switch tabName {
        case "notes":
            suffix = " — Разбор нейросетью"
            defaultContent = target.notesMarkdown
        case "quiz":
            suffix = " — Вопросы к зачёту"
            defaultContent = target.quizMarkdown
        case "final":
            suffix = " — Стенограмма"
            defaultContent = target.finalMarkdown
        case "raw":
            suffix = " — Сырой звук"
            defaultContent = target.rawMarkdown
        default:
            suffix = ""
            defaultContent = target.studentNotesMarkdown.isEmpty ? target.notesMarkdown : target.studentNotesMarkdown
        }
        let content = customContent ?? defaultContent
        let baseName = WhispFormatting.safePathComponent(target.title)
        panel.nameFieldStringValue = "\(baseName)\(suffix).md"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try Data(content.utf8).write(to: url, options: .atomic)
                statusMessage = "Файл сохранён: \(url.lastPathComponent)"
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func exportAudioFile(session: LectureSession? = nil, source: AudioSource = .microphone) {
        let target = session ?? currentSession ?? displayedSession
        guard let target else { return }
        let targetID = target.id
        Task { @MainActor in
            do {
                let dir = try await store.directory(for: targetID)
                let fileName = source == .microphone ? "Микрофон.m4a" : "Системный звук.m4a"
                let sourceFile = dir.appending(path: fileName)
                guard FileManager.default.fileExists(atPath: sourceFile.path) else {
                    lastError = "Файл аудиозаписи не найден (\(fileName))"
                    return
                }
                let panel = NSSavePanel()
                panel.title = "Экспорт аудиозаписи"
                let safeTitle = WhispFormatting.safePathComponent(target.title)
                panel.nameFieldStringValue = "\(safeTitle) — \(fileName)"
                panel.canCreateDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    try FileManager.default.copyItem(at: sourceFile, to: url)
                    statusMessage = "Аудиофайл сохранён: \(url.lastPathComponent)"
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func printLecture(session: LectureSession? = nil, content: String? = nil) {
        let target = session ?? currentSession ?? displayedSession
        guard let target else { return }
        let printContent = content ?? (target.studentNotesMarkdown.isEmpty ? target.notesMarkdown : target.studentNotesMarkdown)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        textView.string = "# \(target.title)\n\nПредмет: \(target.subject)\n\n" + printContent
        let printOp = NSPrintOperation(view: textView)
        printOp.run()
    }

    func generateQuiz(for sessionID: UUID? = nil) async {
        let targetID = sessionID ?? currentSession?.id
        guard let targetID, let index = sessions.firstIndex(where: { $0.id == targetID }) else { return }
        var session = sessions[index]
        let transcriptText = session.finalTranscript.isEmpty ? session.rawTranscript.map(\.text).joined(separator: " ") : session.finalTranscript.map(\.text).joined(separator: " ")
        guard !transcriptText.isEmpty else {
            lastError = "Стенограмма пуста, невозможно составить вопросы"
            return
        }
        guard !settingsStore.activeProviderAPIKeys.isEmpty else {
            lastError = "Укажите API key активного провайдера в настройках"
            return
        }

        isGeneratingQuiz = true
        defer { isGeneratingQuiz = false }

        statusMessage = "Составляем карточки и вопросы через \(settingsStore.activeProviderName)..."
        let prompt = """
        Ты — преподаватель и наставник для подготовки к экзаменам и зачётам.
        На основе приведённой расшифровки лекции составь блок для самопроверки студента в формате Obsidian Markdown:

        # 🎯 Подготовка к зачёту: \(session.title)

        ## ❓ Контрольные вопросы с разбором
        Составь 5-7 глубоких вопросов по теме с развёрнутыми правильными ответами. Оформи каждый вопрос через спойлер/коллаут Obsidian:
        > [!question] Вопрос: [Суть вопроса]
        > > [!success]- Показать правильный ответ
        > > [Развёрнутый ответ с пояснением, формулами в LaTeX и примерами]

        ## 📇 Карточки для запоминания (Flashcards)
        Составь 5 ключевых понятий, определений или законов:
        > [!example] Термин: [[Название]]
        > > [!tip]- Определение
        > > [Чёткое определение]

        ## ⚠️ Опасные места на зачёте (типичные ошибки)
        Дай ровно 3 типичные ошибки студентов. Для каждой используй отдельный блок строго такого вида:
        **Короткое название ошибки**
        **Ошибка:**
        • Что студент делает или понимает неверно
        **Как правильно:**
        • Краткое правильное объяснение

        РАСШИФРОВКА:
        \(transcriptText.prefix(25000))
        """

        do {
            let client = try providerClient()
            let rawQuiz = try await client.generateText(prompt: prompt, model: settingsStore.activeAnalysisModel)
            session.quizMarkdown = WhispFormatting.formatMarkdownNotes(rawQuiz)
            sessions[index] = session
            if currentSession?.id == targetID {
                currentSession = session
            }
            try? await store.save(session)
            statusMessage = "Вопросы к зачёту подготовлены!"
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Ошибка создания вопросов: \(error.localizedDescription)"
        }
    }

    private func makeCoordinator() -> TranscriptionCoordinator {
        TranscriptionCoordinator(
            apiKey: settingsStore.activeProviderSupportsLiveTranscription ? settingsStore.geminiAPIKey : "",
            proxy: settingsStore.proxy,
            settings: settingsStore.settings,
            liveUnavailableMessage: settingsStore.activeProviderSupportsLiveTranscription
                ? "Ключ Gemini не настроен"
                : "Live-расшифровка доступна только через Gemini; используется локальный Whisper",
            elapsed: { [clock] in clock.elapsed() },
            callbacks: .init(
                onSegment: { [weak self] segment in Task { @MainActor in self?.receive(segment: segment) } },
                onFallbackOpened: { [weak self] interval in Task { @MainActor in self?.openFallback(interval) } },
                onFallbackClosed: { [weak self] end in Task { @MainActor in self?.closeFallback(at: end) } },
                onStatus: { [weak self] status in Task { @MainActor in self?.statusMessage = status } },
                onGeminiState: { [weak self] state in
                    Task { @MainActor in
                        self?.geminiState = state
                        self?.proxyState = self?.settingsStore.proxy.isEnabled == true ? state : .disabled
                    }
                },
                onWhisperState: { [weak self] state in Task { @MainActor in self?.whisperState = state } }
            )
        )
    }

    private func receive(segment: TranscriptSegment) {
        guard var session = currentSession else { return }
        session.rawTranscript = TranscriptMerger.merge(session.rawTranscript + [segment])
        session.finalTranscript = TranscriptMerger.merge(session.finalTranscript + [segment])
        currentSession = session
        Task { try? await persistCurrent() }
    }

    private func receive(chunk: AudioChunk) {
        guard var session = currentSession else { return }
        session.audioChunks.append(chunk)
        currentSession = session
        Task { try? await persistCurrent() }
    }

    private func openFallback(_ interval: FallbackInterval) {
        guard var session = currentSession, !session.fallbackIntervals.contains(where: \.isOpen) else { return }
        session.fallbackIntervals.append(interval)
        currentSession = session
        Task { try? await persistCurrent() }
    }

    private func closeFallback(at end: TimeInterval) {
        guard var session = currentSession,
              let index = session.fallbackIntervals.lastIndex(where: \.isOpen) else { return }
        session.fallbackIntervals[index].end = end
        session.fallbackIntervals[index].status = .pending
        currentSession = session
        Task { try? await persistCurrent() }
    }

    private func beginBackfillMonitorIfNeeded() {
        backfillMonitor?.cancel()
        guard currentSession?.hasPendingBackfill == true, !settingsStore.activeProviderAPIKeys.isEmpty else { return }
        let sessionID = currentSession?.id
        backfillMonitor = Task { [weak self] in
            var delay = 60.0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, self.currentSession?.id == sessionID else { return }
                do {
                    let client = try self.providerClient()
                    let service = BackfillService(client: client, model: self.settingsStore.activeTranscriptionModel, vocabulary: self.settingsStore.settings.customVocabulary, processor: self.processor)
                    try await service.checkAvailability()
                    guard !Task.isCancelled, !self.isBusy,
                          var session = self.currentSession, session.id == sessionID else { return }
                    for index in session.fallbackIntervals.indices where ![.accepted, .declined].contains(session.fallbackIntervals[index].status) {
                        session.fallbackIntervals[index].status = .available
                    }
                    self.currentSession = session
                    self.showBackfillPrompt = true
                    await service.notifyAvailable(sessionTitle: session.title)
                    try? await self.persistCurrent()
                    return
                } catch {
                    if let api = error as? GeminiAPIError, let retry = api.retryAfter { delay = min(3_600, max(30, retry)) }
                    else { delay = min(3_600, delay * 2) }
                }
            }
        }
    }

    private func scheduleSyncRetry() {
        guard syncRetryTask == nil || syncRetryTask?.isCancelled == true else { return }
        let sessionID = currentSession?.id
        syncRetryTask = Task { [weak self] in
            var delay = 60.0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, self.currentSession?.id == sessionID, self.currentSession?.status == .uploading else { return }
                await self.syncCurrent()
                if self.currentSession?.status == .synced { return }
                delay = min(3_600, delay * 2)
            }
        }
    }

    private func ensureMix(session: LectureSession, directory: URL) async throws -> URL {
        if let currentMixURL, currentMixURL.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
           FileManager.default.fileExists(atPath: currentMixURL.path) { return currentMixURL }
        // Includes imports made by older versions, which had no audioChunks metadata.
        let microphone = directory.appending(path: "Микрофон.m4a")
        if session.audioChunks.isEmpty {
            if FileManager.default.fileExists(atPath: microphone.path) {
                currentMixURL = microphone
                return microphone
            }
            if let original = session.importedAudioPath {
                let prepared = try await processor.prepareImportedAudio(source: directory.appending(path: original), directory: directory)
                currentMixURL = prepared
                return prepared
            }
        }
        let savedMix = directory.appending(path: "Обработка-микс.m4a")
        if FileManager.default.fileExists(atPath: savedMix.path) {
            currentMixURL = savedMix
            return savedMix
        }
        let outputs = try await processor.finalize(session: session, directory: directory)
        currentMixURL = outputs.mix
        return outputs.mix
    }

    func addProcessingLog(_ message: String) {
        let entry = ProcessingLogEntry(message: message)
        processingLogs.append(entry)
    }

    func clearProcessingLogs() {
        processingLogs.removeAll()
        processingCurrentChunk = 0
        processingTotalChunks = 0
        processingChunkRange = ""
        processingStartTime = Date()
    }

    var processingElapsedFormatted: String {
        guard let start = processingStartTime else { return "00:00" }
        let elapsed = max(0, Date().timeIntervalSince(start))
        return WhispFormatting.timestamp(elapsed)
    }

    var processingRemainingFormatted: String? {
        guard let start = processingStartTime, processingProgress > 0.05, processingProgress < 0.99 else { return nil }
        let elapsed = max(0, Date().timeIntervalSince(start))
        let totalEstimated = elapsed / processingProgress
        let remaining = max(0, totalEstimated - elapsed)
        if remaining < 5 { return "почти готово" }
        return "осталось ~\(WhispFormatting.durationDescription(remaining))"
    }

    private func progressHandler(sessionID: UUID) -> @Sendable (TranscriptionProgress) async -> Void {
        { [weak self] update in
            await self?.receiveProgress(update, sessionID: sessionID)
        }
    }

    private func receiveProgress(_ update: TranscriptionProgress, sessionID: UUID) async {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var session = sessions[index]
        guard session.status == .processing else { return }
        if session.audioChunks.isEmpty { session.rawTranscript = update.segments }
        session.finalTranscript = update.segments
        sessions[index] = session
        try? await store.save(session)

        if currentSession?.id == sessionID {
            currentSession = session
        }

        processingProgress = 0.08 + update.progress * 0.72
        processingCurrentChunk = update.currentChunk
        processingTotalChunks = update.totalChunks
        if update.chunkEnd > update.chunkStart {
            processingChunkRange = "\(WhispFormatting.timestamp(update.chunkStart)) – \(WhispFormatting.timestamp(update.chunkEnd))"
        }
        statusMessage = update.stageDescription
        if let log = update.logMessage {
            addProcessingLog(log)
        }
    }

    private func geminiClient() -> GeminiAPIClient {
        GeminiAPIClient(apiKeys: settingsStore.geminiAPIKeys, proxy: settingsStore.proxy)
    }

    private func providerClient() throws -> GeminiAPIClient {
        guard let endpoint = settingsStore.activeProviderEndpoint else {
            throw GeminiAPIError(
                code: -1,
                status: "PROVIDER_URL",
                message: "Укажите корректный базовый URL активного провайдера",
                retryAfter: nil
            )
        }
        guard !settingsStore.activeProviderAPIKeys.isEmpty else {
            throw GeminiAPIError(
                code: 401,
                status: "API_KEY",
                message: "Укажите API key активного провайдера",
                retryAfter: nil
            )
        }
        return GeminiAPIClient(
            apiKeys: settingsStore.activeProviderAPIKeys,
            proxy: settingsStore.proxy,
            baseURL: endpoint,
            transport: settingsStore.activeProviderTransport
        )
    }

    private func persistCurrent() async throws {
        guard let currentSession else { return }
        try await store.save(currentSession)
        if let index = sessions.firstIndex(where: { $0.id == currentSession.id }) { sessions[index] = currentSession }
        else { sessions.insert(currentSession, at: 0) }
    }

    private func toggleRecordingFromHotKey() {
        if isRecording { Task { await pauseOrResume() } }
        else { Task { await startRecording() } }
    }
}
