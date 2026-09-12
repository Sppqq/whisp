import AVFoundation
import XCTest
@testable import Whisp

final class AudioImportTests: XCTestCase {
    func testExampleRecordingSlicesAndImport() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appending(path: "ex.m4a")
        guard FileManager.default.fileExists(atPath: source.path) else { throw XCTSkip("ex.m4a is not present") }
        let directory = FileManager.default.temporaryDirectory.appending(path: "WhispTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let localSource = directory.appending(path: "test-source.m4a")
        do {
            try FileManager.default.copyItem(at: source, to: localSource)
        } catch {
            throw XCTSkip("Cannot copy ex.m4a to test directory: \(error)")
        }
        let asset = AVURLAsset(url: localSource)
        let duration: Double
        do {
            duration = try await asset.load(.duration).seconds
        } catch {
            throw XCTSkip("AVFoundation cannot access ex.m4a in test runner sandbox: \(error)")
        }
        XCTAssertGreaterThan(duration, 0)
        let processor = AudioPostProcessor()
        // Exercise the real codec at beginning, middle and EOF without cloud calls.
        for start in [0, duration / 2, max(0, duration - 2)] {
            let slice = directory.appending(path: "slice.m4a")
            try await processor.slice(source: localSource, start: start, end: min(duration, start + 2), destination: slice)
            let imported = try await processor.prepareImportedAudio(source: slice, directory: directory)
            let importedAsset = AVURLAsset(url: imported)
            let importedDuration = try await importedAsset.load(.duration).seconds
            XCTAssertGreaterThan(importedDuration, 0)
            XCTAssertLessThanOrEqual(importedDuration, 8.2)
        }
    }

    func testAACImport() async throws {
        let aacURL = URL(fileURLWithPath: "/Users/sppq/Downloads/Physics.aac")
        guard FileManager.default.fileExists(atPath: aacURL.path) else { return }
        let directory = FileManager.default.temporaryDirectory.appending(path: "WhispTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let processor = AudioPostProcessor()
        let imported = try await processor.prepareImportedAudio(source: aacURL, directory: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.path))
        let asset = AVURLAsset(url: imported)
        let duration = try await asset.load(.duration).seconds
        XCTAssertGreaterThan(duration, 400)
    }
}
