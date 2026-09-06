import XCTest
@testable import Whisp

final class SessionStoreTests: XCTestCase {
    func testRoundTripAndRecovery() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = SessionStore(baseDirectory: base)
        var session = LectureSession()
        session.status = .recording
        session.startedAt = Date()
        session.importedAudioPath = "Исходник-ex.m4a"
        try await store.save(session)
        let loaded = try await store.load(session.id)
        XCTAssertEqual(loaded.id, session.id)
        XCTAssertEqual(loaded.importedAudioPath, session.importedAudioPath)
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
