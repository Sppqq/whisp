import Foundation

actor WebDAVClient {
    enum WebDAVError: LocalizedError {
        case invalidURL, writeNotSupported, unexpectedStatus(Int, String), verificationFailed(String)
        var errorDescription: String? {
            switch self {
            case .invalidURL: "Некорректный адрес WebDAV"
            case .writeNotSupported:
                "WebDAV доступен для чтения, но сервер не разрешает запись методом PUT. Проверьте права удалённого хранилища; для rclone отключите режим --read-only."
            case .unexpectedStatus(let code, let message): "WebDAV вернул \(code): \(message)"
            case .verificationFailed(let path): "Не удалось проверить загруженный файл: \(path)"
            }
        }
    }

    private let configuration: WebDAVConfiguration
    private let session: URLSession

    init(configuration: WebDAVConfiguration) {
        self.configuration = configuration
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = 30
        sessionConfiguration.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: sessionConfiguration)
    }

    func checkConnection() async throws {
        let root = configuration.rootFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = try remoteURL(path: root)
        try await checkWriteCapability(at: url)
        var request = authenticatedRequest(url: url, method: "PROPFIND")
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.httpBody = Data("<?xml version=\"1.0\"?><propfind xmlns=\"DAV:\"><prop><displayname/></prop></propfind>".utf8)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, accepted: [200, 207], request: request)
    }

    func upload(session lecture: LectureSession, localDirectory: URL) async throws -> String {
        try await checkConnection()
        var remotePath = lecture.remotePath ?? WhispFormatting.lecturePath(for: lecture, root: configuration.rootFolder)
        var pathAlreadyExists = false
        if lecture.remotePath == nil {
            pathAlreadyExists = try await exists(path: remotePath)
        }
        if pathAlreadyExists {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH-mm"
            remotePath += " — " + formatter.string(from: lecture.startedAt ?? lecture.createdAt)
        }
        try await ensureDirectories(remotePath)
        let lessonName = WhispFormatting.safePathComponent(lecture.title)
        let markdown = MarkdownExporter.render(session: lecture)
        var files: [(String, Data)] = [
            ("\(lessonName).md", Data((lecture.studentNotesMarkdown.isEmpty ? markdown.studentNotebook : lecture.studentNotesMarkdown).utf8)),
            ("\(lessonName) — Разбор нейросетью.md", Data((lecture.notesMarkdown.isEmpty ? markdown.notes : lecture.notesMarkdown).utf8)),
            ("\(lessonName) — Стенограмма.md", Data((lecture.finalMarkdown.isEmpty ? markdown.final : lecture.finalMarkdown).utf8)),
            ("\(lessonName) — Сырой звук.md", Data((lecture.rawMarkdown.isEmpty ? markdown.raw : lecture.rawMarkdown).utf8))
        ]
        if !lecture.quizMarkdown.isEmpty {
            let quizData = markdown.quiz.isEmpty ? lecture.quizMarkdown : markdown.quiz
            files.append(("\(lessonName) — Вопросы к зачёту.md", Data(quizData.utf8)))
        }
        for (name, data) in files {
            try await atomicUpload(data: data, remotePath: remotePath + "/" + name)
        }

        for legacy in [
            "Тетрадь (под запись).md",
            "Конспект (подробный).md",
            "Оригинальная транскрипция.md",
            "Сырая транскрипция.md",
            "Конспект.md",
            "\(lessonName) — Подробный разбор.md"
        ] {
            _ = try? await delete(path: remotePath + "/" + legacy)
        }

        // Clean up any legacy subject hub note if present
        if lecture.subject != "Не определено" {
            let subjectName = WhispFormatting.safePathComponent(lecture.subject)
            _ = try? await delete(path: "\(configuration.rootFolder)/\(subjectName).md")
        }

        for name in ["Микрофон.m4a", "Системный звук.m4a"] {
            let url = localDirectory.appending(path: name)
            if FileManager.default.fileExists(atPath: url.path) {
                try await atomicUpload(fileURL: url, remotePath: remotePath + "/" + name)
            }
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sessionData = try encoder.encode(lecture)
        try await atomicUpload(data: sessionData, remotePath: remotePath + "/session.json", expectedETag: lecture.remoteETag)
        return remotePath
    }

    struct RemoteEntry {
        let path: String
        let isDirectory: Bool
    }

    func downloadData(remotePath: String) async throws -> Data {
        let url = try remoteURL(path: remotePath)
        let request = authenticatedRequest(url: url, method: "GET")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, accepted: [200], request: request)
        return data
    }

    /// Returns true when the remote session changed after this Mac last synced it.
    /// Servers without ETag/Last-Modified metadata are treated as unknown and do
    /// not block an upload; the existing atomic PUT path remains the fallback.
    func hasRemoteConflict(for lecture: LectureSession) async throws -> Bool {
        guard let remotePath = lecture.remotePath else { return false }

        let metadata = try await remoteMetadata(path: remotePath + "/session.json")
        guard metadata.exists else { return false }

        if let expectedETag = lecture.remoteETag, let actualETag = metadata.etag {
            return expectedETag != actualETag
        }
        if lecture.remoteETag != nil { return true }
        if let syncedAt = lecture.syncedAt, let modifiedAt = metadata.lastModified {
            return modifiedAt > syncedAt.addingTimeInterval(1)
        }
        return true
    }

    func remoteETag(path: String) async throws -> String? {
        (try await remoteMetadata(path: path + "/session.json")).etag
    }

    private struct RemoteMetadata {
        let exists: Bool
        let etag: String?
        let lastModified: Date?
    }

    private func remoteMetadata(path: String) async throws -> RemoteMetadata {
        let url = try remoteURL(path: path)
        let request = authenticatedRequest(url: url, method: "HEAD")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.verificationFailed(url.lastPathComponent)
        }
        if http.statusCode == 404 { return RemoteMetadata(exists: false, etag: nil, lastModified: nil) }
        if [405, 501].contains(http.statusCode) {
            let get = authenticatedRequest(url: url, method: "GET")
            let (_, getResponse) = try await session.data(for: get)
            guard let getHTTP = getResponse as? HTTPURLResponse else { throw WebDAVError.verificationFailed(url.lastPathComponent) }
            if getHTTP.statusCode == 404 { return RemoteMetadata(exists: false, etag: nil, lastModified: nil) }
            guard (200..<300).contains(getHTTP.statusCode) else { throw WebDAVError.unexpectedStatus(getHTTP.statusCode, "Не удалось проверить удалённую версию") }
            return RemoteMetadata(exists: true, etag: getHTTP.value(forHTTPHeaderField: "ETag"), lastModified: Self.parseHTTPDate(getHTTP.value(forHTTPHeaderField: "Last-Modified")))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WebDAVError.unexpectedStatus(http.statusCode, "Не удалось проверить удалённую версию")
        }
        return RemoteMetadata(
            exists: true,
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: Self.parseHTTPDate(http.value(forHTTPHeaderField: "Last-Modified"))
        )
    }

    private static func parseHTTPDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }

    func listRemoteTree(root: String) async throws -> [RemoteEntry] {
        let url = try remoteURL(path: root)
        var request = authenticatedRequest(url: url, method: "PROPFIND")
        request.setValue("infinity", forHTTPHeaderField: "Depth")
        let (data, response) = try await session.data(for: request)
        guard let xmlString = String(data: data, encoding: .utf8) else { return [] }
        return parseMultistatusXML(xmlString)
    }

    private func parseMultistatusXML(_ xml: String) -> [RemoteEntry] {
        var results: [RemoteEntry] = []
        let responsePattern = "(?s)<(?:\\w+:)?response>(.*?)</(?:\\w+:)?response>"
        guard let responseRegex = try? NSRegularExpression(pattern: responsePattern, options: .caseInsensitive) else { return [] }
        let hrefRegex = try? NSRegularExpression(pattern: "<(?:\\w+:)?href>(.*?)</(?:\\w+:)?href>", options: .caseInsensitive)
        let collectionRegex = try? NSRegularExpression(pattern: "<(?:\\w+:)?collection\\s*/?>", options: .caseInsensitive)

        let basePath = (try? baseURL().path) ?? ""
        let nsString = xml as NSString
        let matches = responseRegex.matches(in: xml, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            let chunk = nsString.substring(with: match.range)
            let chunkNS = chunk as NSString
            guard let hrefMatch = hrefRegex?.firstMatch(in: chunk, options: [], range: NSRange(location: 0, length: chunkNS.length)),
                  hrefMatch.numberOfRanges > 1 else { continue }

            let rawHref = chunkNS.substring(with: hrefMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let decodedHref = rawHref.removingPercentEncoding else { continue }

            let isCollection = (collectionRegex?.numberOfMatches(in: chunk, options: [], range: NSRange(location: 0, length: chunkNS.length)) ?? 0) > 0

            var path = decodedHref
            if !basePath.isEmpty && basePath != "/" && path.hasPrefix(basePath) {
                path.removeFirst(basePath.count)
            }
            if path.hasSuffix("/") && path.count > 1 {
                path.removeLast()
            }
            results.append(RemoteEntry(path: path, isDirectory: isCollection))
        }
        return results
    }

    func restoreFromWebDAV(to store: SessionStore, onProgress: ((String) -> Void)? = nil) async throws -> Int {
        onProgress?("Поиск лекций на WebDAV...")
        let root = configuration.rootFolder.trimmingCharacters(in: .whitespaces)
        let entries = try await listRemoteTree(root: root.isEmpty ? "/" : root)

        var filesByFolder: [String: [String]] = [:]
        for entry in entries where !entry.isDirectory {
            let nsPath = entry.path as NSString
            let folder = nsPath.deletingLastPathComponent
            let fileName = nsPath.lastPathComponent
            filesByFolder[folder, default: []].append(fileName)
        }

        let lectureFolders = filesByFolder.keys.filter { folder in
            let files = filesByFolder[folder] ?? []
            return files.contains("session.json") || files.contains(where: { $0.hasSuffix(".md") })
        }.sorted()

        var restoredCount = 0
        let existingSessions = try await store.loadAll()

        for folder in lectureFolders {
            let files = filesByFolder[folder] ?? []
            let folderName = (folder as NSString).lastPathComponent

            // Check if existing session matches this remote lecture
            let alreadyExists = existingSessions.contains { session in
                if let remote = session.remotePath, remote == folder { return true }
                if session.title == folderName { return true }
                return false
            }

            if alreadyExists {
                continue
            }

            if files.contains("session.json") {
                onProgress?("Загрузка: \(folderName)...")
                do {
                    let sessionData = try await downloadData(remotePath: folder + "/session.json")
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    var session = try decoder.decode(LectureSession.self, from: sessionData)
                    session.remotePath = folder
                    session.remoteETag = try? await remoteETag(path: folder)
                    session.status = .synced
                    session.syncedAt = Date()

                    let dir = try await store.directory(for: session.id)

                    for audioName in ["Микрофон.m4a", "Системный звук.m4a"] {
                        if files.contains(audioName) {
                            let targetAudio = dir.appending(path: audioName)
                            if !FileManager.default.fileExists(atPath: targetAudio.path) {
                                if let audioData = try? await downloadData(remotePath: folder + "/" + audioName) {
                                    try? audioData.write(to: targetAudio, options: .atomic)
                                }
                            }
                        }
                    }

                    try await store.save(session)
                    restoredCount += 1
                } catch {
                    print("Error restoring session.json from \(folder): \(error)")
                }
            } else {
                onProgress?("Восстановление: \(folderName)...")
                do {
                    var finalMarkdown = ""
                    var rawMarkdown = ""
                    var notesMarkdown = ""
                    var studentNotesMarkdown = ""
                    var quizMarkdown = ""
                    var sampleMarkdownForFrontmatter = ""

                    for file in files where file.hasSuffix(".md") {
                        guard let data = try? await downloadData(remotePath: folder + "/" + file),
                              let content = String(data: data, encoding: .utf8) else { continue }

                        if file.contains("— Стенограмма") {
                            finalMarkdown = content
                        } else if file.contains("— Сырой звук") {
                            rawMarkdown = content
                        } else if file.contains("— Разбор нейросетью") || file.contains("— Подробный разбор") {
                            notesMarkdown = content
                        } else if file.contains("— Вопросы к зачёту") {
                            quizMarkdown = content
                        } else {
                            studentNotesMarkdown = content
                            sampleMarkdownForFrontmatter = content
                        }
                        if sampleMarkdownForFrontmatter.isEmpty {
                            sampleMarkdownForFrontmatter = content
                        }
                    }

                    let title = FrontmatterParser.parseValue(key: "title", in: sampleMarkdownForFrontmatter) ?? folderName
                    let subject = FrontmatterParser.parseValue(key: "subject", in: sampleMarkdownForFrontmatter) ?? "Не определено"
                    let dateStr = FrontmatterParser.parseValue(key: "date", in: sampleMarkdownForFrontmatter)
                    let startedAt: Date?
                    if let dateStr {
                        startedAt = ISO8601DateFormatter().date(from: dateStr)
                    } else {
                        startedAt = nil
                    }

                    let transcriptSegments = FrontmatterParser.parseSegments(from: finalMarkdown.isEmpty ? rawMarkdown : finalMarkdown)

                    let session = LectureSession(
                        id: UUID(),
                        createdAt: startedAt ?? Date(),
                        startedAt: startedAt ?? Date(),
                        endedAt: nil,
                        status: .synced,
                        title: title,
                        subject: subject,
                        isPinned: false,
                        captureSystemAudio: files.contains("Системный звук.m4a"),
                        importedAudioPath: nil,
                        rawTranscript: transcriptSegments,
                        finalTranscript: transcriptSegments,
                        fallbackIntervals: [],
                        audioChunks: [],
                        pauses: [],
                        analysis: nil,
                        rawMarkdown: rawMarkdown,
                        finalMarkdown: finalMarkdown,
                        notesMarkdown: notesMarkdown,
                        studentNotesMarkdown: studentNotesMarkdown,
                        quizMarkdown: quizMarkdown,
                        lastError: nil,
                        syncedAt: Date(),
                        remotePath: folder,
                        userEditedFinal: false,
                        userEditedNotes: false,
                        userEditedStudentNotes: false
                    )

                    let dir = try await store.directory(for: session.id)

                    for audioName in ["Микрофон.m4a", "Системный звук.m4a"] {
                        if files.contains(audioName) {
                            let targetAudio = dir.appending(path: audioName)
                            if !FileManager.default.fileExists(atPath: targetAudio.path) {
                                if let audioData = try? await downloadData(remotePath: folder + "/" + audioName) {
                                    try? audioData.write(to: targetAudio, options: .atomic)
                                }
                            }
                        }
                    }

                    try await store.save(session)
                    restoredCount += 1
                } catch {
                    print("Error reconstructing lecture from \(folder): \(error)")
                }
            }
        }

        return restoredCount
    }

    private func delete(path: String) async throws {
        let url = try remoteURL(path: path)
        let request = authenticatedRequest(url: url, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, accepted: [200, 204, 404], request: request)
    }

    private func exists(path: String) async throws -> Bool {
        var request = authenticatedRequest(url: try remoteURL(path: path), method: "PROPFIND")
        request.setValue("0", forHTTPHeaderField: "Depth")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        if http.statusCode == 404 { return false }
        try validate(response, data: data, accepted: [200, 207], request: request)
        return true
    }

    private func ensureDirectories(_ path: String) async throws {
        var components: [String] = []
        for component in path.split(separator: "/").map(String.init) {
            components.append(component)
            let remotePath = components.joined(separator: "/")
            let url = try remoteURL(path: components.joined(separator: "/"))
            var request = authenticatedRequest(url: url, method: "MKCOL")
            request.httpBody = Data()
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               http.statusCode == 405,
               try await exists(path: remotePath) {
                continue
            }
            try validate(response, data: data, accepted: [201, 204, 301], request: request)
        }
    }

    /// Upload directly to the final path. MOVE is optional in practice and
    /// simple WebDAV servers often answer 405 for temporary-file promotion.
    private func atomicUpload(fileURL: URL, remotePath: String) async throws {
        let finalURL = try remoteURL(path: remotePath)
        let put = authenticatedRequest(url: finalURL, method: "PUT")
        let (_, response) = try await session.upload(for: put, fromFile: fileURL)
        try validate(response, data: nil, accepted: [200, 201, 204], request: put)
        try await verify(url: finalURL, expectedLength: (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue)
    }

    private func atomicUpload(data: Data, remotePath: String, expectedETag: String? = nil) async throws {
        let finalURL = try remoteURL(path: remotePath)
        var put = authenticatedRequest(url: finalURL, method: "PUT")
        put.httpBody = data
        if let expectedETag {
            put.setValue(expectedETag, forHTTPHeaderField: "If-Match")
        }
        let (responseData, response) = try await session.data(for: put)
        try validate(response, data: responseData, accepted: [200, 201, 204], request: put)
        try await verify(url: finalURL, expectedLength: data.count)
    }

    private func verify(url: URL, expectedLength: Int?) async throws {
        let request = authenticatedRequest(url: url, method: "HEAD")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.verificationFailed(url.lastPathComponent)
        }
        // HEAD is optional on a few lightweight WebDAV implementations. The
        // successful PUT above is enough to accept the upload in that case.
        if [405, 501].contains(http.statusCode) { return }
        guard (200..<300).contains(http.statusCode) else {
            throw WebDAVError.verificationFailed(url.lastPathComponent)
        }
        if let expectedLength,
           let value = http.value(forHTTPHeaderField: "Content-Length"),
           let actual = Int(value), actual != expectedLength {
            throw WebDAVError.verificationFailed(url.lastPathComponent)
        }
    }

    private func checkWriteCapability(at url: URL) async throws {
        let request = authenticatedRequest(url: url, method: "OPTIONS")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }

        // OPTIONS is optional for WebDAV clients. If it is not implemented,
        // let PROPFIND below perform the connectivity check and let PUT be the
        // final authority for servers that do not advertise Allow.
        if [405, 501].contains(http.statusCode) { return }
        try validate(response, data: data, accepted: [200, 204], request: request)

        guard let allow = http.value(forHTTPHeaderField: "Allow") else { return }
        let methods = Set(
            allow.split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespaces).uppercased()
            }
        )
        if !methods.contains("PUT") {
            throw WebDAVError.writeNotSupported
        }
    }

    private func baseURL() throws -> URL {
        guard let url = URL(string: configuration.baseURL), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw WebDAVError.invalidURL
        }
        return url
    }

    private func remoteURL(path: String) throws -> URL {
        var url = try baseURL()
        for component in path.split(separator: "/") { url.append(path: String(component)) }
        return url
    }

    private func authenticatedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if !configuration.username.isEmpty {
            let token = Data("\(configuration.username):\(configuration.password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func validate(_ response: URLResponse, data: Data?, accepted: [Int], request: URLRequest? = nil) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard accepted.contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let method = request?.httpMethod ?? "HTTP"
            let path = request?.url?.path ?? ""
            let allow = http.value(forHTTPHeaderField: "Allow").map { "; Allow: \($0)" } ?? ""
            let operation = "[\(method) \(path)\(allow)]"
            throw WebDAVError.unexpectedStatus(http.statusCode, "\(String(body.prefix(240))) \(operation)")
        }
    }
}

enum FrontmatterParser {
    static func parseValue(key: String, in text: String) -> String? {
        let pattern = "(?m)^\\s*\(key):\\s*\"?([^\"\\n\\r]+)\"?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)),
              match.numberOfRanges > 1 else { return nil }
        return (text as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
    }

    static func parseSegments(from transcriptMarkdown: String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        let lines = transcriptMarkdown.components(separatedBy: .newlines)
        let pattern = "^\\[(\\d{1,2}:\\d{2}(?::\\d{2})?)\\]\\s*(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for line in lines {
            let ns = line as NSString
            guard let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: ns.length)),
                  match.numberOfRanges > 2 else { continue }
            let timeStr = ns.substring(with: match.range(at: 1))
            let text = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }

            let parts = timeStr.split(separator: ":").compactMap { Double($0) }
            let seconds: TimeInterval
            if parts.count == 3 {
                seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
            } else if parts.count == 2 {
                seconds = parts[0] * 60 + parts[1]
            } else {
                seconds = 0
            }

            segments.append(TranscriptSegment(
                id: UUID(),
                start: seconds,
                end: seconds + 3.0,
                text: text,
                source: .geminiLive,
                model: "restored"
            ))
        }

        for i in 0..<segments.count {
            if i + 1 < segments.count {
                segments[i].end = max(segments[i].start + 1.0, segments[i + 1].start)
            }
        }
        return segments
    }
}
