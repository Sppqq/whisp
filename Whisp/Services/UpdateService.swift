import AppKit
import Foundation
import Observation

struct AppVersion: Comparable, Equatable, Sendable {
    let numbers: [Int]
    let prerelease: String?

    init?(_ rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0 == "v" || $0 == "V" })
        let parts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numericParts = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard !numericParts.isEmpty,
              numericParts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        numbers = numericParts.map { Int($0) ?? 0 }
        prerelease = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<count {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right }
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (.some, nil): return true
        case (nil, .some): return false
        case let (.some(left), .some(right)): return left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

struct WhispRelease: Identifiable, Equatable, Sendable {
    let version: String
    let title: String
    let notes: String
    let pageURL: URL
    let downloadURL: URL
    let isPrerelease: Bool

    var id: String { version }
}

enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(WhispRelease)
    case downloading(WhispRelease)
    case downloaded(WhispRelease, URL)
    case failed(String)
}

@MainActor
@Observable
final class UpdateService {
    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case draft
            case prerelease
            case assets
        }
    }

    private static let releasesURL = URL(string: "https://api.github.com/repos/Sppqq/whisp/releases?per_page=20")!
    private let defaults: UserDefaults
    private let session: URLSession

    private(set) var state: UpdateState = .idle
    var automaticallyChecksForUpdates: Bool {
        didSet { defaults.set(automaticallyChecksForUpdates, forKey: "automaticallyChecksForUpdates") }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var availableRelease: WhispRelease? {
        if case .available(let release) = state { return release }
        return nil
    }

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        if defaults.object(forKey: "automaticallyChecksForUpdates") == nil {
            automaticallyChecksForUpdates = true
        } else {
            automaticallyChecksForUpdates = defaults.bool(forKey: "automaticallyChecksForUpdates")
        }
    }

    func checkForUpdates(silent: Bool = false) async {
        if !silent { state = .checking }
        do {
            var request = URLRequest(url: Self.releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Whisp/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.unavailable
            }
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            if let release = Self.newestRelease(from: releases, newerThan: currentVersion) {
                state = .available(release)
            } else if !silent {
                state = .upToDate
            }
        } catch {
            if !silent { state = .failed(error.localizedDescription) }
        }
    }

    func downloadAndOpen(_ release: WhispRelease) async {
        state = .downloading(release)
        do {
            var request = URLRequest(url: release.downloadURL)
            request.setValue("Whisp/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (temporaryURL, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.downloadFailed
            }
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Whisp/Updates", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("Whisp-\(release.version).dmg")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            state = .downloaded(release, destination)
            NSWorkspace.shared.open(destination)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func openReleasePage(_ release: WhispRelease) {
        NSWorkspace.shared.open(release.pageURL)
    }

    func dismissAvailableUpdate() {
        if case .available = state { state = .idle }
    }

    private static func newestRelease(from releases: [GitHubRelease], newerThan current: String) -> WhispRelease? {
        guard let currentVersion = AppVersion(current) else { return nil }
        return releases
            .filter { !$0.draft }
            .compactMap { release -> (AppVersion, WhispRelease)? in
                guard let version = AppVersion(release.tagName), version > currentVersion,
                      let asset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else { return nil }
                let cleanVersion = String(release.tagName.drop(while: { $0 == "v" || $0 == "V" }))
                return (version, WhispRelease(
                    version: cleanVersion,
                    title: release.name ?? "Whisp \(cleanVersion)",
                    notes: release.body ?? "",
                    pageURL: release.htmlURL,
                    downloadURL: asset.browserDownloadURL,
                    isPrerelease: release.prerelease
                ))
            }
            .max(by: { $0.0 < $1.0 })?
            .1
    }
}

private enum UpdateError: LocalizedError {
    case unavailable
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: "Не удалось получить список релизов GitHub"
        case .downloadFailed: "Не удалось скачать DMG обновления"
        }
    }
}
