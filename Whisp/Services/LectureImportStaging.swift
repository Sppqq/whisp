import Foundation

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
