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
    case installing(WhispRelease)
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
    private static let releasesPageURL = URL(string: "https://github.com/Sppqq/whisp/releases")!
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

    init(defaults: UserDefaults = .standard, session: URLSession? = nil) {
        self.defaults = defaults
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: configuration)
        }
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
            guard let http = response as? HTTPURLResponse else { throw UpdateError.unavailable }
            switch http.statusCode {
            case 200: break
            case 404: throw UpdateError.privateRepository
            case 403: throw UpdateError.rateLimited
            default: throw UpdateError.unavailable
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

    var updatesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Whisp/Updates", isDirectory: true)
    }

    var targetAppURL: URL {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" && !bundle.path.contains("DerivedData") && !bundle.path.contains("/Build/Products/") {
            return bundle
        }
        return URL(fileURLWithPath: "/Applications/Whisp.app")
    }

    func installUpdate(_ release: WhispRelease) async {
        state = .downloading(release)
        do {
            let directory = updatesDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destinationDMG = directory.appendingPathComponent("Whisp-\(release.version).dmg")

            var request = URLRequest(url: release.downloadURL)
            request.setValue("Whisp/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (temporaryURL, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.downloadFailed
            }

            if FileManager.default.fileExists(atPath: destinationDMG.path) {
                try FileManager.default.removeItem(at: destinationDMG)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destinationDMG)

            state = .installing(release)

            let mountPoint = directory.appendingPathComponent("Mount_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

            var isMounted = false
            defer {
                if isMounted {
                    _ = try? runProcess(executable: "/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force"])
                }
                try? FileManager.default.removeItem(at: mountPoint)
            }

            _ = try runProcess(
                executable: "/usr/bin/hdiutil",
                arguments: ["attach", destinationDMG.path, "-mountpoint", mountPoint.path, "-nobrowse", "-readonly", "-noautoopen"]
            )
            isMounted = true

            let contents = try FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
            guard let appInMount = contents.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError.invalidPackage("В скачанном DMG не найден файл Whisp.app")
            }

            let infoPlistURL = appInMount.appendingPathComponent("Contents/Info.plist")
            guard FileManager.default.fileExists(atPath: infoPlistURL.path),
                  let infoData = try? Data(contentsOf: infoPlistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
                  let bundleId = plist["CFBundleIdentifier"] as? String,
                  bundleId == "app.whisp.lectures" else {
                throw UpdateError.invalidPackage("Файл приложения в DMG имеет некорректный идентификатор")
            }

            let executableURL = appInMount.appendingPathComponent("Contents/MacOS/Whisp")
            guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
                throw UpdateError.invalidPackage("Файл приложения в DMG не содержит исполняемого бинарного файла")
            }

            let stagingDirectory = directory.appendingPathComponent("Staging", isDirectory: true)
            if FileManager.default.fileExists(atPath: stagingDirectory.path) {
                try FileManager.default.removeItem(at: stagingDirectory)
            }
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            let stagedApp = stagingDirectory.appendingPathComponent("Whisp.app", isDirectory: true)

            _ = try runProcess(executable: "/usr/bin/ditto", arguments: [appInMount.path, stagedApp.path])

            _ = try runProcess(executable: "/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force"])
            isMounted = false

            let scriptURL = directory.appendingPathComponent("install_and_restart.sh")
            let logURL = directory.appendingPathComponent("updater.log")
            let scriptContent = Self.updaterScriptContent

            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            _ = try runProcess(executable: "/bin/chmod", arguments: ["+x", scriptURL.path])

            let currentPID = ProcessInfo.processInfo.processIdentifier
            let targetURL = targetAppURL

            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
            launcher.arguments = [
                "-c",
                "nohup \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" </dev/null >/dev/null 2>&1 &",
                "bash",
                scriptURL.path,
                "\(currentPID)",
                stagedApp.path,
                targetURL.path,
                logURL.path
            ]
            try launcher.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApplication.shared.terminate(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    exit(0)
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    private nonisolated func runProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw UpdateError.processFailed("Команда \(executable) завершилась с ошибкой (\(process.terminationStatus)): \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }

    static let updaterScriptContent = #"""
    #!/bin/bash
    set -e
    trap '' HUP INT TERM
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

    PID="$1"
    STAGE_APP="$2"
    TARGET_APP="$3"
    LOG_FILE="$4"

    exec > "$LOG_FILE" 2>&1
    echo "=== Whisp Auto-Updater ==="
    echo "Date: $(date)"
    echo "Waiting for process $PID to terminate..."

    for i in {1..30}; do
        if ! kill -0 "$PID" 2>/dev/null; then
            echo "Process $PID exited."
            break
        fi
        sleep 0.5
    done

    if kill -0 "$PID" 2>/dev/null; then
        echo "Process $PID still running after 15s. Sending SIGKILL..."
        kill -9 "$PID" 2>/dev/null || true
        sleep 0.5
    fi

    if [ ! -d "$STAGE_APP" ]; then
        echo "ERROR: Stage app does not exist at $STAGE_APP"
        exit 1
    fi

    TARGET_DIR="$(dirname "$TARGET_APP")"
    CAN_WRITE=1
    if [ -e "$TARGET_APP" ] && [ ! -w "$TARGET_APP" ]; then CAN_WRITE=0; fi
    if [ -e "$TARGET_DIR" ] && [ ! -w "$TARGET_DIR" ]; then CAN_WRITE=0; fi

    echo "Replacing $TARGET_APP with $STAGE_APP (writable=$CAN_WRITE)..."

    if [ "$CAN_WRITE" -eq 1 ]; then
        BACKUP_APP="${TARGET_APP}.old.$$"
        rm -rf "$BACKUP_APP"
        if [ -d "$TARGET_APP" ]; then
            mv "$TARGET_APP" "$BACKUP_APP" 2>/dev/null || rm -rf "$TARGET_APP" 2>/dev/null || true
        fi
        if ditto "$STAGE_APP" "$TARGET_APP"; then
            rm -rf "$BACKUP_APP" 2>/dev/null || true
            echo "Direct replacement succeeded."
        else
            echo "Direct replacement failed. Restoring backup..."
            if [ -d "$BACKUP_APP" ]; then
                mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null || true
            fi
            exit 1
        fi
    else
        echo "Administrator privileges required. Requesting via osascript..."
        osascript -e "do shell script \"rm -rf '$TARGET_APP' && ditto '$STAGE_APP' '$TARGET_APP' && xattr -dr com.apple.quarantine '$TARGET_APP'\" with administrator privileges"
    fi

    xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

    echo "Cleaning up staging..."
    STAGE_DIR="$(dirname "$STAGE_APP")"
    rm -rf "$STAGE_DIR" 2>/dev/null || true

    echo "Relaunching $TARGET_APP..."
    open "$TARGET_APP"
    echo "Update complete."
    """#

    func openReleasePage(_ release: WhispRelease) {
        NSWorkspace.shared.open(release.pageURL)
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(Self.releasesPageURL)
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
    case privateRepository
    case rateLimited
    case downloadFailed
    case invalidPackage(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Не удалось получить список релизов GitHub"
        case .privateRepository: "Репозиторий Whisp пока приватный. Автообновление заработает после открытия репозитория."
        case .rateLimited: "GitHub временно ограничил проверку обновлений. Попробуйте позже."
        case .downloadFailed: "Не удалось скачать DMG обновления"
        case .invalidPackage(let reason): "Образ обновления повреждён: \(reason)"
        case .processFailed(let reason): "Ошибка выполнения команды обновления: \(reason)"
        }
    }
}
