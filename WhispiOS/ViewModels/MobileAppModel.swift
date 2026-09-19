import AVFoundation
import Foundation
import Observation
import SwiftUI

enum MobileTranscriptionMode: String, CaseIterable, Identifiable {
    case cloud = "cloud"
    case automatic = "automatic"
    case local = "local"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cloud: "Облако"
        case .automatic: "Авто: облако → Whisper"
        case .local: "Только локальный Whisper"
        }
    }
}

@MainActor
@Observable
final class MobileAppModel {
    var sessions: [LectureSession] = []
    var selectedSessionID: UUID?
    var isRecording = false
    var isProcessing = false
    var isImporting = false
    var processingProgress = ""
    var errorMessage: String?
    var searchQuery = ""
    var transcriptionMode: MobileTranscriptionMode = MobileTranscriptionMode(rawValue: UserDefaults.standard.string(forKey: "ios.transcriptionMode") ?? "") ?? .cloud {
        didSet { UserDefaults.standard.set(transcriptionMode.rawValue, forKey: "ios.transcriptionMode") }
    }
    var isCheckingWebDAV = false
    var isRestoringWebDAV = false
    var webDAVStatus = ""
    var isCheckingProvider = false
    var providerStatus = ""
    var reminderAccessStatus = ""
    var reminderAccessGranted = ReminderService.hasFullAccess

    private let store = SessionStore.shared
    private let recorder = MobileAudioRecorder()
    var settingsStore = SettingsStore()
    private var searchIndex = LibrarySearchIndex()
    private var activeSessionID: UUID?

    var apiKey: String {
        get { settingsStore.geminiAPIKey }
        set { settingsStore.geminiAPIKey = newValue }
    }

    var appearance: WhispAppearance {
        get { settingsStore.settings.appearance }
        set {
            var updated = settingsStore.settings
            updated.appearance = newValue
            settingsStore.settings = updated
        }
    }

    var activeProviderName: String { settingsStore.activeProviderName }

    var visibleSessions: [LectureSession] {
        let ids = searchIndex.matchingIDs(for: searchQuery)
        return sessions.filter { ids.contains($0.id) }
    }

    var selectedSession: LectureSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    init() {}

    func load() async {
        do {
            sessions = try await store.loadAll()
            searchIndex.rebuild(sessions: sessions)
            if selectedSessionID == nil { selectedSessionID = sessions.first?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRecording() async {
        guard !isRecording, !isProcessing else { return }
        do {
            var session = LectureSession(status: .recording, captureSystemAudio: false)
            session.startedAt = Date()
            let directory = try await store.directory(for: session.id)
            let audioURL = directory.appending(path: "Микрофон.m4a")
            try await recorder.start(at: audioURL)
            try await store.save(session)
            sessions.insert(session, at: 0)
            selectedSessionID = session.id
            activeSessionID = session.id
            isRecording = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishRecording() async {
        guard isRecording, let id = activeSessionID,
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        recorder.stop()
        isRecording = false
        activeSessionID = nil
        sessions[index].endedAt = Date()
        sessions[index].status = .processing
        sessions[index].importedAudioPath = "Микрофон.m4a"
        do {
            try await store.save(sessions[index])
            let directory = try await store.directory(for: id)
            await process(sessionID: id, audioURL: directory.appending(path: "Микрофон.m4a"))
        } catch {
            fail(sessionID: id, error: error)
        }
    }

    func importAudio(_ source: URL) async {
        guard !isRecording, !isProcessing else { return }
        isImporting = true
        processingProgress = "Сжимаем аудио…"
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped { source.stopAccessingSecurityScopedResource() }
            isImporting = false
        }

        var session = LectureSession(status: .processing, captureSystemAudio: false)
        session.startedAt = Date()
        session.endedAt = Date()
        do {
            let directory = try await store.directory(for: session.id)
            // Store the normalized import under the same canonical name as a
            // microphone recording so Markdown export and WebDAV sync include it.
            let destination = directory.appending(path: "Микрофон.m4a")
            _ = try await MobileAudioCompressor().compress(
                source: source,
                destination: destination,
                onProgress: { [weak self] progress in
                    self?.processingProgress = "Сжимаем аудио… \(Int(progress * 100))%"
                }
            )
            session.importedAudioPath = destination.lastPathComponent
            try await store.save(session)
            sessions.insert(session, at: 0)
            selectedSessionID = session.id
            await process(sessionID: session.id, audioURL: destination)
        } catch {
            fail(sessionID: session.id, error: error)
        }
    }

    func delete(_ session: LectureSession) async {
        do {
            try await store.delete(session.id)
            sessions.removeAll { $0.id == session.id }
            searchIndex.rebuild(sessions: sessions)
            if selectedSessionID == session.id { selectedSessionID = sessions.first?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retry(_ session: LectureSession) async {
        guard !isRecording, !isProcessing, let relativePath = session.importedAudioPath else { return }
        do {
            let directory = try await store.directory(for: session.id)
            let audioURL = directory.appending(path: relativePath)
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw MobileError.audioMissing
            }
            var pending = session
            pending.status = .processing
            pending.lastError = nil
            replace(pending)
            try await store.save(pending)
            await process(sessionID: session.id, audioURL: audioURL)
        } catch {
            fail(sessionID: session.id, error: error)
        }
    }

    func update(_ session: LectureSession) async {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index] = session
        searchIndex.rebuild(sessions: sessions)
        do { try await store.save(session) }
        catch { errorMessage = error.localizedDescription }
    }

    func updateContent(sessionID: UUID, section: LectureSection, content: String) async {
        guard var session = sessions.first(where: { $0.id == sessionID }) else { return }
        switch section {
        case .notebook: session.studentNotesMarkdown = content; session.userEditedStudentNotes = true
        case .analysis: session.notesMarkdown = content; session.userEditedNotes = true
        case .transcript: session.finalMarkdown = content; session.userEditedFinal = true
        case .quiz: session.quizMarkdown = content
        }
        await update(session)
    }

    func updateMetadata(sessionID: UUID, title: String, subject: String) async {
        guard var session = sessions.first(where: { $0.id == sessionID }) else { return }
        session.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Новая лекция" : title
        session.subject = subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Не определено" : subject
        await update(session)
    }

    func updateQuizProgress(sessionID: UUID, progress: QuizProgress) async {
        guard var session = sessions.first(where: { $0.id == sessionID }) else { return }
        session.quizProgress = progress
        await update(session)
    }

    func updateGeminiKey(at index: Int, value: String) {
        var keys = settingsStore.geminiAPIKeys
        guard keys.indices.contains(index) else { return }
        keys[index] = value
        settingsStore.geminiAPIKeys = keys
    }

    func saveGeminiKeys(_ keys: [String]) {
        settingsStore.geminiAPIKeys = keys
    }

    func addGeminiKey() {
        var keys = settingsStore.geminiAPIKeys
        keys.append("")
        settingsStore.geminiAPIKeys = keys
    }

    func removeGeminiKey(at index: Int) {
        var keys = settingsStore.geminiAPIKeys
        guard keys.indices.contains(index) else { return }
        keys.remove(at: index)
        settingsStore.geminiAPIKeys = keys
    }

    func addScheduleEntry() {
        var settings = settingsStore.settings
        settings.lessonSchedule.append(LessonScheduleEntry())
        settingsStore.settings = settings
    }

    func removeScheduleEntry(_ id: UUID) {
        var settings = settingsStore.settings
        settings.lessonSchedule.removeAll { $0.id == id }
        settingsStore.settings = settings
    }

    func generateQuiz(for sessionID: UUID) async {
        guard !isProcessing, var session = sessions.first(where: { $0.id == sessionID }) else { return }
        let transcript = (session.finalTranscript.isEmpty ? session.rawTranscript : session.finalTranscript)
            .map(\.text).joined(separator: " ")
        guard !transcript.isEmpty else { errorMessage = "Стенограмма пуста, невозможно составить вопросы."; return }
        guard settingsStore.isActiveProviderConfigured else { errorMessage = "Настройте активный провайдер в параметрах."; return }
        isProcessing = true
        processingProgress = "Готовим вопросы…"
        defer { isProcessing = false }
        do {
            let client = makeClient()
            let prompt = """
            Ты — преподаватель. На основе расшифровки лекции составь блок самопроверки в Markdown Obsidian.
            Заголовок: # 🎯 Подготовка к зачёту: \(session.title)
            Дай 5–7 вопросов с развёрнутыми ответами, 5 карточек терминов и ровно 3 типичные ошибки.
            Не добавляй факты, которых нет в расшифровке. Используй понятные заголовки и списки.

            РАСШИФРОВКА:
            \(transcript.prefix(25_000))
            """
            let raw = try await client.generateText(prompt: prompt, model: settingsStore.activeAnalysisModel)
            session.quizMarkdown = WhispFormatting.formatMarkdownNotes(raw)
            session.quizProgress.reset()
            await update(session)
            processingProgress = "Вопросы готовы"
        } catch { errorMessage = error.localizedDescription }
    }

    func sync(_ session: LectureSession) async {
        guard !settingsStore.webDAV.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Настройте WebDAV в параметрах."
            return
        }
        do {
            processingProgress = "Синхронизация с WebDAV…"
            let directory = try await store.directory(for: session.id)
            let path = try await WebDAVClient(configuration: settingsStore.webDAV).upload(session: session, localDirectory: directory)
            var updated = session
            updated.remotePath = path
            updated.syncedAt = Date()
            updated.status = .synced
            await update(updated)
            processingProgress = "Синхронизировано"
        } catch { errorMessage = error.localizedDescription }
    }

    func checkWebDAV() async {
        guard !settingsStore.webDAV.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            webDAVStatus = "Укажите адрес WebDAV"
            return
        }
        isCheckingWebDAV = true
        webDAVStatus = "Проверяем…"
        defer { isCheckingWebDAV = false }
        do {
            try await WebDAVClient(configuration: settingsStore.webDAV).checkConnection()
            webDAVStatus = "Подключение работает"
        } catch {
            webDAVStatus = "Ошибка: \(error.localizedDescription)"
        }
    }

    func checkProvider() async {
        guard settingsStore.activeProviderEndpoint != nil else {
            providerStatus = "Укажите корректный адрес endpoint"
            return
        }
        guard settingsStore.isActiveProviderConfigured else {
            providerStatus = "Добавьте API key для выбранного провайдера"
            return
        }
        isCheckingProvider = true
        providerStatus = "Проверяем подключение…"
        defer { isCheckingProvider = false }
        do {
            let client = GeminiAPIClient(
                apiKeys: settingsStore.activeProviderAPIKeys,
                proxy: settingsStore.proxy,
                baseURL: settingsStore.activeProviderEndpoint ?? GeminiAPIClient.defaultBaseURL,
                transport: settingsStore.activeProviderTransport
            )
            try await client.probeTranscription(settingsStore.activeTranscriptionModel)
            providerStatus = "Подключение работает"
        } catch {
            providerStatus = "Ошибка: \(error.localizedDescription)"
        }
    }

    func requestReminderAccess() async {
        do {
            let granted = try await ReminderService().requestAccess()
            reminderAccessGranted = granted
            reminderAccessStatus = granted ? "Доступ к Reminders разрешён" : "Доступ запрещён"
        } catch { reminderAccessStatus = error.localizedDescription }
    }

    func refreshReminderAccess() {
        reminderAccessGranted = ReminderService.hasFullAccess
    }

    func restoreFromWebDAV() async {
        guard !settingsStore.webDAV.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Настройте WebDAV в параметрах."
            return
        }
        isRestoringWebDAV = true
        defer { isRestoringWebDAV = false }
        do {
            processingProgress = "Загрузка лекций с WebDAV…"
            _ = try await WebDAVClient(configuration: settingsStore.webDAV).restoreFromWebDAV(to: store)
            sessions = try await store.loadAll()
            searchIndex.rebuild(sessions: sessions)
            processingProgress = "Библиотека обновлена"
        } catch { errorMessage = error.localizedDescription }
    }

    func createReminders(for session: LectureSession) async {
        guard settingsStore.settings.remindersEnabled, let drafts = session.analysis?.reminders, !drafts.isEmpty else {
            errorMessage = "Для этой лекции нет заданий для напоминаний."
            return
        }
        do {
            let ids = try await ReminderService().createReminders(
                drafts: drafts,
                session: session,
                schedule: settingsStore.settings.lessonSchedule,
                listIdentifier: settingsStore.settings.reminderListIdentifier
            )
            var updated = session
            updated.createdReminderIDs.append(contentsOf: ids)
            await update(updated)
            processingProgress = ids.isEmpty ? "Нет будущих сроков" : "Создано напоминаний: \(ids.count)"
        } catch { errorMessage = error.localizedDescription }
    }

    private func process(sessionID: UUID, audioURL: URL) async {
        if transcriptionMode == .local {
            await processLocally(sessionID: sessionID, audioURL: audioURL, originalError: MobileError.localMode)
            return
        }
        if settingsStore.activeProviderRequiresAPIKey && settingsStore.activeProviderAPIKeys.isEmpty {
            if transcriptionMode == .automatic {
                await processLocally(sessionID: sessionID, audioURL: audioURL, originalError: MobileError.missingAPIKey)
            } else { fail(sessionID: sessionID, error: MobileError.missingAPIKey) }
            return
        }
        isProcessing = true
        processingProgress = "Подготовка аудио…"
        defer { isProcessing = false }

        do {
            let client = makeClient()
            let progress = MobileProgressReporter(model: self)
            let segments = try await client.transcribe(
                audioURL: audioURL,
                model: settingsStore.activeTranscriptionModel,
                vocabulary: settingsStore.settings.customVocabulary,
                onStatus: { status in
                    await progress.report(status)
                }
            )
            guard var session = sessions.first(where: { $0.id == sessionID }) else { return }
            session.rawTranscript = segments
            session.finalTranscript = segments
            session.status = .processing
            try await store.save(session)
            replace(session)

            processingProgress = "Создаём конспект…"
            let analysisService = LectureAnalysisService(
                client: client,
                model: settingsStore.activeAnalysisModel,
                fallbackModels: settingsStore.activeAnalysisFallbackModels
            )
            let analysis = try await analysisService.analyze(
                segments: segments,
                subjects: settingsStore.settings.subjects.filter(\.isEnabled).sorted { $0.order < $1.order }.map(\.name),
                onStatus: { status in
                    await progress.report(status)
                }
            )
            session.analysis = analysis
            session.title = analysis.title
            session.subject = analysis.subject
            session.status = .review
            let rendered = MarkdownExporter.render(session: session)
            session.studentNotesMarkdown = rendered.studentNotebook
            session.notesMarkdown = rendered.notes
            session.finalMarkdown = rendered.final
            session.rawMarkdown = rendered.raw
            try await store.save(session)
            replace(session)
            processingProgress = "Готово"
        } catch {
            if transcriptionMode == .automatic {
                await processLocally(sessionID: sessionID, audioURL: audioURL, originalError: error)
            } else {
                fail(sessionID: sessionID, error: error)
            }
        }
    }

    private func processLocally(sessionID: UUID, audioURL: URL, originalError: Error) async {
        do {
            processingProgress = "Локальный Whisper: первая загрузка модели может занять время…"
            let segments = try await MobileLocalTranscriptionService().transcribe(audioURL: audioURL)
            guard var session = sessions.first(where: { $0.id == sessionID }) else { return }
            session.rawTranscript = segments
            session.finalTranscript = segments
            session.fallbackIntervals = []
            session.lastError = transcriptionMode == .automatic
                ? "Обработано локальным Whisper после ошибки сети: \(originalError.localizedDescription)"
                : nil

            if transcriptionMode == .local {
                // The local-only mode must not call the cloud analysis service.
                // Keep the transcript usable immediately and leave the optional
                // AI-generated notebook empty until the user chooses a cloud mode.
                session.status = .review
                let rendered = MarkdownExporter.render(session: session)
                session.studentNotesMarkdown = rendered.studentNotebook
                session.notesMarkdown = rendered.notes
                session.finalMarkdown = rendered.final
                session.rawMarkdown = rendered.raw
                await update(session)
                processingProgress = "Готово (локальный Whisper)"
                return
            }

            let client = makeClient()
            let service = LectureAnalysisService(client: client, model: settingsStore.activeAnalysisModel, fallbackModels: settingsStore.activeAnalysisFallbackModels)
            let analysis = try await service.analyze(segments: segments, subjects: settingsStore.settings.subjects.filter(\.isEnabled).map(\.name))
            session.analysis = analysis
            session.title = analysis.title
            session.subject = analysis.subject
            session.status = .review
            let rendered = MarkdownExporter.render(session: session)
            session.studentNotesMarkdown = rendered.studentNotebook
            session.notesMarkdown = rendered.notes
            session.finalMarkdown = rendered.final
            session.rawMarkdown = rendered.raw
            await update(session)
            processingProgress = "Готово (локальный Whisper)"
        } catch { fail(sessionID: sessionID, error: error) }
    }

    private func makeClient() -> GeminiAPIClient {
        GeminiAPIClient(
            apiKeys: settingsStore.activeProviderAPIKeys,
            proxy: settingsStore.proxy,
            baseURL: settingsStore.activeProviderEndpoint ?? GeminiAPIClient.defaultBaseURL,
            transport: settingsStore.activeProviderTransport
        )
    }

    private func replace(_ session: LectureSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
            sessions.sort { $0.createdAt > $1.createdAt }
            searchIndex.rebuild(sessions: sessions)
        }
    }

    private func fail(sessionID: UUID, error: Error) {
        if var session = sessions.first(where: { $0.id == sessionID }) {
            session.status = .failed
            session.lastError = error.localizedDescription
            replace(session)
            Task { try? await store.save(session) }
        }
        errorMessage = error.localizedDescription
    }

}

private struct MobileProgressReporter: @unchecked Sendable {
    weak var model: MobileAppModel?

    @MainActor
    func report(_ status: String) {
        model?.processingProgress = status
    }
}

private enum MobileError: LocalizedError {
    case missingAPIKey, audioMissing, localMode
    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Добавьте API key активного провайдера в настройках Whisp."
        case .audioMissing: "Исходный аудиофайл этой лекции не найден."
        case .localMode: "Локальная расшифровка WhisperKit."
        }
    }
}
