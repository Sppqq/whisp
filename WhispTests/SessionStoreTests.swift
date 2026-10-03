import XCTest
@testable import Whisp

final class SessionStoreTests: XCTestCase {
    func testTextImportCombinesPastedTextAndFilesAndPreservesOriginals() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let destination = root.appending(path: "lecture")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "Лекция.md")
        let data = Data("# Тема\nИсходные заметки".utf8)
        try data.write(to: source)
        let text = try LectureImportContent.prepareText(files: [source], pasted: "Дополнение", directory: destination)
        XCTAssertTrue(text.contains("Дополнение"))
        XCTAssertTrue(text.contains("Исходные заметки"))
        XCTAssertEqual(try Data(contentsOf: source), data)
        XCTAssertEqual(try Data(contentsOf: destination.appending(path: "Текст-1-Лекция.md")), data)
        XCTAssertEqual(LectureImportContent.segments(text).first?.source, .importedText)
    }

    func testAppendingMaterialsPreservesEditedNotesAndMarksCloudChanges() {
        var session = LectureSession()
        session.status = .synced
        session.syncedAt = Date()
        session.studentNotesMarkdown = "Мой конспект"
        session.notesMarkdown = "Мой разбор"
        session.userEditedStudentNotes = true
        session.finalMarkdown = "Существующая стенограмма"
        session.finalTranscript = LectureImportContent.segments("Исходная лекция")
        let originalID = session.finalTranscript[0].id
        LectureImportContent.append(LectureImportContent.segments("Новый материал"), to: &session)
        XCTAssertEqual(session.finalTranscript.count, 2)
        XCTAssertEqual(session.finalTranscript[0].id, originalID)
        XCTAssertTrue(session.finalMarkdown.contains("Существующая стенограмма"))
        XCTAssertTrue(session.finalMarkdown.contains("Новый материал"))
        XCTAssertEqual(session.studentNotesMarkdown, "Мой конспект")
        XCTAssertEqual(session.notesMarkdown, "Мой разбор")
        XCTAssertTrue(session.userEditedStudentNotes)
        XCTAssertEqual(session.cloudSyncTitle, "Есть изменения на Mac")
        LectureImportContent.append(LectureImportContent.segments("Ещё одно дополнение"), to: &session)
        XCTAssertEqual(session.finalTranscript.count, 3)
    }

    func testUTF16TextAndVideoClassification() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "Запись.txt")
        try XCTUnwrap("Русский текст".data(using: .utf16)).write(to: source)
        let decoded = try LectureImportContent.prepareText(files: [source], pasted: "", directory: root)
        XCTAssertTrue(decoded.contains("Русский текст"))
        XCTAssertTrue(LectureImportContent.isMedia(URL(fileURLWithPath: "/clip.mp4")))
        XCTAssertTrue(LectureImportContent.isMedia(URL(fileURLWithPath: "/clip.mov")))
        XCTAssertFalse(LectureImportContent.isMedia(URL(fileURLWithPath: "/notes.md")))
        XCTAssertThrowsError(try LectureImportContent.prepareText(files: [], pasted: String(repeating: "a", count: 5_000_001), directory: root))
    }

    @MainActor
    func testSyncReportsBusyOperationInsteadOfSilentlyIgnoringClick() async {
        let model = AppModel()
        model.currentSession = LectureSession()
        model.isRestoringFromWebDAV = true
        await model.syncCurrent()
        XCTAssertNotNil(model.lastError)
        XCTAssertEqual(model.currentSession?.status, .draft)
    }

    @MainActor
    func testNewLectureDuringBackgroundNotesKeepsProgressAndAllowsRecording() {
        let model = AppModel()
        model.isGeneratingNotes = true
        model.statusMessage = "Создаём конспект"
        model.showStartScreen()
        XCTAssertEqual(model.statusMessage, "Создаём конспект")
        XCTAssertTrue(model.canStartRecording)
        XCTAssertTrue(model.isBusy)
        model.isRestoringFromWebDAV = true
        XCTAssertFalse(model.canStartRecording)
        XCTAssertNotNil(model.recordingUnavailableReason)
    }

    func testCloudStatusDistinguishesUploadFailureAndLocalChanges() {
        var session = LectureSession()
        XCTAssertEqual(session.cloudSyncTitle, "Только на Mac")
        session.status = .synced
        session.syncedAt = Date()
        XCTAssertEqual(session.cloudSyncTitle, "В облаке")
        session.status = .review
        XCTAssertEqual(session.cloudSyncTitle, "Есть изменения на Mac")
        session.status = .uploading
        XCTAssertEqual(session.cloudSyncTitle, "Загрузка в облако")
        session.lastError = "Нет сети"
        XCTAssertEqual(session.cloudSyncTitle, "Ошибка загрузки")
    }

    func testRoundTripAndRecovery() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = SessionStore(baseDirectory: base)
        var session = LectureSession()
        session.status = .recording
        session.startedAt = Date()
        session.importedAudioPath = "Исходник-ex.m4a"
        let completedReminderID = UUID()
        session.completedReminderIDs = [completedReminderID]
        try await store.save(session)
        let loaded = try await store.load(session.id)
        XCTAssertEqual(loaded.id, session.id)
        XCTAssertEqual(loaded.importedAudioPath, session.importedAudioPath)
        XCTAssertEqual(loaded.completedReminderIDs, [completedReminderID])
        let recoverable = try await store.recoverableSessions().map(\.id)
        XCTAssertEqual(recoverable, [session.id])
    }

    func testOlderSessionWithoutImportMetadataStillDecodes() throws {
        let data = try JSONEncoder().encode(LectureSession())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "importedAudioPath")
        let oldData = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try JSONDecoder().decode(LectureSession.self, from: oldData).importedAudioPath)
    }

    func testLegacySessionWithoutQuizAndNotebookDecodes() throws {
        let jsonString = """
        {
            "id": "0731E325-F9D9-4AAA-BD92-827E8E104CE4",
            "createdAt": "2026-09-04T14:30:56Z",
            "title": "Тестовая лекция",
            "subject": "Физика",
            "status": "review"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(LectureSession.self, from: Data(jsonString.utf8))
        XCTAssertEqual(session.title, "Тестовая лекция")
        XCTAssertEqual(session.subject, "Физика")
        XCTAssertEqual(session.quizMarkdown, "")
        XCTAssertEqual(session.studentNotesMarkdown, "")
        XCTAssertTrue(session.completedReminderIDs.isEmpty)
    }

    func testReminderCanBeCompletedRestoredAndDeleted() {
        let reminder = ReminderDraft(title: "Сделать упражнение", notes: "№ 5")
        var session = LectureSession(analysis: AnalysisResult(
            title: "Алгебра",
            subject: "Математика",
            confidence: 1,
            alternatives: [],
            summary: "",
            detailedNotes: "",
            reminders: [reminder]
        ))

        session.toggleReminderCompletion(reminder.id)
        XCTAssertTrue(session.completedReminderIDs.contains(reminder.id))

        session.toggleReminderCompletion(reminder.id)
        XCTAssertFalse(session.completedReminderIDs.contains(reminder.id))

        session.toggleReminderCompletion(reminder.id)
        session.deleteReminder(reminder.id)
        XCTAssertTrue(session.analysis?.reminders.isEmpty == true)
        XCTAssertFalse(session.completedReminderIDs.contains(reminder.id))
    }

    func testLegacySettingsKeepExistingValuesAndDefaultToGemini() throws {
        let legacy = #"{"geminiModel":"gemini-test","analysisModel":"gemini-analysis","localRetentionDays":14}"#
        let settings = try JSONDecoder().decode(WhispSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(settings.geminiModel, "gemini-test")
        XCTAssertEqual(settings.analysisModel, "gemini-analysis")
        XCTAssertEqual(settings.localRetentionDays, 14)
        XCTAssertEqual(settings.activeProviderID, "gemini")
    }

    func testCustomProviderAcceptsOnlyHTTPOrHTTPSEndpoints() {
        var provider = CustomProvider(baseURL: "https://api.example.test")
        XCTAssertEqual(provider.endpoint?.host, "api.example.test")
        provider.baseURL = "file:///tmp/provider"
        XCTAssertNil(provider.endpoint)
    }

    func testLoadRealSessionsDirectory() async throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let sessionsDir = appSupport.appending(path: "Whisp/Sessions", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: sessionsDir.path) {
            let store = SessionStore(baseDirectory: sessionsDir)
            let sessions = try await store.loadAll()
            print("Loaded \(sessions.count) sessions from real directory!")
            XCTAssertGreaterThanOrEqual(sessions.count, 1)
        }
    }
}
