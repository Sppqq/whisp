import Foundation

actor SessionStore {
    static let shared = SessionStore()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let sessionsDirectory: URL

    init(baseDirectory: URL? = nil) {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let baseDirectory {
            sessionsDirectory = baseDirectory
        } else {
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            sessionsDirectory = applicationSupport.appending(path: "Whisp/Sessions", directoryHint: .isDirectory)
        }
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    }

    func directory(for sessionID: UUID) throws -> URL {
        try prepare()
        let url = sessionsDirectory.appending(path: sessionID.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func save(_ session: LectureSession) throws {
        let dir = try directory(for: session.id)
        let url = dir.appending(path: "session.json")
        let temporary = url.appendingPathExtension("tmp")
        try encoder.encode(session).write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }

        // Save local .md files so they are easily accessible in Finder / Obsidian
        let lessonName = WhispFormatting.safePathComponent(session.title)
        let markdown = MarkdownExporter.render(session: session)
        let mainContent = session.studentNotesMarkdown.isEmpty ? markdown.studentNotebook : session.studentNotesMarkdown
        let notesContent = session.notesMarkdown.isEmpty ? markdown.notes : session.notesMarkdown
        let finalContent = session.finalMarkdown.isEmpty ? markdown.final : session.finalMarkdown
        let rawContent = session.rawMarkdown.isEmpty ? markdown.raw : session.rawMarkdown

        if !mainContent.isEmpty {
            try? Data(mainContent.utf8).write(to: dir.appending(path: "\(lessonName).md"), options: .atomic)
        }
        if !notesContent.isEmpty {
            try? Data(notesContent.utf8).write(to: dir.appending(path: "\(lessonName) — Разбор нейросетью.md"), options: .atomic)
        }
        if !finalContent.isEmpty {
            try? Data(finalContent.utf8).write(to: dir.appending(path: "\(lessonName) — Стенограмма.md"), options: .atomic)
        }
        if !rawContent.isEmpty {
            try? Data(rawContent.utf8).write(to: dir.appending(path: "\(lessonName) — Сырой звук.md"), options: .atomic)
        }
        if !session.quizMarkdown.isEmpty {
            let quizData = markdown.quiz.isEmpty ? session.quizMarkdown : markdown.quiz
            try? Data(quizData.utf8).write(to: dir.appending(path: "\(lessonName) — Вопросы к зачёту.md"), options: .atomic)
        }
    }

    func load(_ id: UUID) throws -> LectureSession {
        let url = sessionsDirectory.appending(path: id.uuidString).appending(path: "session.json")
        return try decoder.decode(LectureSession.self, from: Data(contentsOf: url))
    }

    func loadAll() throws -> [LectureSession] {
        try prepare()
        let urls = try FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls.compactMap { directory in
            let metadata = directory.appending(path: "session.json")
            guard let data = try? Data(contentsOf: metadata) else { return nil }
            do {
                return try decoder.decode(LectureSession.self, from: data)
            } catch {
                print("SessionStore: Failed to decode session at \(directory.path): \(error)")
                return nil
            }
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func recoverableSessions() throws -> [LectureSession] {
        try loadAll().filter { [.recording, .paused, .processing, .uploading].contains($0.status) }
    }

    func removeExpiredSessions(now: Date = Date(), retentionDays: Int) throws {
        let expiration = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        for session in try loadAll() where !session.isPinned && session.status == .synced {
            guard let syncedAt = session.syncedAt, syncedAt < expiration else { continue }
            let target = sessionsDirectory.appending(path: session.id.uuidString, directoryHint: .isDirectory)
            let resolved = target.standardizedFileURL
            guard resolved.path.hasPrefix(sessionsDirectory.standardizedFileURL.path + "/") else { continue }
            try FileManager.default.removeItem(at: resolved)
        }
    }

    func delete(_ id: UUID) throws {
        let target = sessionsDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
        let resolved = target.standardizedFileURL
        guard resolved.path.hasPrefix(sessionsDirectory.standardizedFileURL.path + "/") else { return }
        if FileManager.default.fileExists(atPath: resolved.path) {
            try FileManager.default.removeItem(at: resolved)
        }
    }
}
