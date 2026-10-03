import Foundation
import UniformTypeIdentifiers

enum LectureImportStaging {
    private static let root = FileManager.default.temporaryDirectory
        .appending(path: "WhispImportStaging", directoryHint: .isDirectory)

    static func writePhoto(_ data: Data, filename: String) throws -> URL {
        let directory = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cleanedName = URL(fileURLWithPath: filename).lastPathComponent
        let destination = directory.appending(path: cleanedName.isEmpty ? "Фото.jpg" : cleanedName)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func cleanup(_ urls: [URL]) {
        let rootPath = root.standardizedFileURL.path + "/"
        let directories = Set(urls.compactMap { url -> URL? in
            let standardized = url.standardizedFileURL
            guard standardized.path.hasPrefix(rootPath) else { return nil }
            return standardized.deletingLastPathComponent()
        })
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

// Shared import classification and text decoding for Mac and iPhone.
enum LectureImportContent {
    static var allowedTypes: [UTType] { [.audio, .movie, .image, .plainText, UTType(filenameExtension: "md") ?? .plainText] }
    static func isMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .video)
    }
    static func isText(_ url: URL) -> Bool {
        ["txt", "md", "markdown", "text"].contains(url.pathExtension.lowercased())
    }
    enum ImportError: LocalizedError {
        case tooLarge, unreadable(String), empty
        var errorDescription: String? {
            switch self {
            case .tooLarge: "Текстовые материалы слишком большие — максимум 5 МБ суммарно."
            case .unreadable(let name): "Не удалось прочитать текст в файле «\(name)». Сохраните его как TXT или Markdown в UTF-8."
            case .empty: "Добавьте непустой текст, фото, аудио или видео."
            }
        }
    }
    static func prepareText(files: [URL], pasted: String, directory: URL) throws -> String {
        var parts: [String] = []
        var byteCount = pasted.utf8.count
        guard byteCount <= 5_000_000 else { throw ImportError.tooLarge }
        if !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(pasted)
            try Data(pasted.utf8).write(to: directory.appending(path: "Вставленный текст.txt"), options: .atomic)
        }
        for (index, url) in files.enumerated() {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard byteCount + size <= 5_000_000 else { throw ImportError.tooLarge }
            let data = try Data(contentsOf: url)
            byteCount += data.count
            guard byteCount <= 5_000_000 else { throw ImportError.tooLarge }
            let hasUTF16BOM = data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff])
            guard let text = String(data: data, encoding: .utf8)
                ?? (hasUTF16BOM ? String(data: data, encoding: .utf16) : String(data: data, encoding: .windowsCP1251)) else {
                throw ImportError.unreadable(url.lastPathComponent)
            }
            let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let filename = "Текст-\(index + 1)-\(WhispFormatting.safePathComponent(url.lastPathComponent))"
            try data.write(to: directory.appending(path: filename), options: .atomic)
            if !cleaned.isEmpty { parts.append("## \(url.deletingPathExtension().lastPathComponent)\n\n\(cleaned)") }
        }
        return parts.joined(separator: "\n\n")
    }
    /// Append sources without rebuilding or replacing the user's edited notes.
    static func append(_ segments: [TranscriptSegment], to session: inout LectureSession) {
        session.rawTranscript.append(contentsOf: segments)
        session.finalTranscript.append(contentsOf: segments)
        if !segments.isEmpty {
            let text = segments.map(\.text).joined(separator: "\n\n")
            session.rawMarkdown += "\n\n" + text
            session.finalMarkdown += "\n\n" + text
        }
        session.status = .review
        session.lastError = nil
    }

    static func segments(_ text: String) -> [TranscriptSegment] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return [TranscriptSegment(start: 0, end: 0, text: text, source: .importedText, model: "Импорт текста", confidence: 1, manuallyEdited: true)]
    }
}
