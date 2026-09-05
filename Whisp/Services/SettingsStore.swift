import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    var settings: WhispSettings { didSet { persist() } }
    var proxy: ProxyConfiguration { didSet { persist() } }
    var webDAV: WebDAVConfiguration { didSet { persist() } }

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cachedGeminiAPIKey = ""
    private var cachedGeminiAPIKeys: [String] = []
    var keyStatuses: [String: GeminiKeyStatus] = [:]

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        let decoder = JSONDecoder()
        var loadedSettings = defaults.data(forKey: "settings")
            .flatMap { try? decoder.decode(WhispSettings.self, from: $0) } ?? WhispSettings()
        if loadedSettings.analysisModel == "gemini-3.7-flash" {
            loadedSettings.analysisModel = "gemini-3.8-flash"
        }

        self.defaults = defaults
        self.keychain = keychain
        settings = loadedSettings

        var loadedProxy = ProxyConfiguration()
        if let configString = try? keychain.get(.proxyConfiguration),
           let data = configString.data(using: .utf8),
           let decoded = try? decoder.decode(ProxyConfiguration.self, from: data) {
            loadedProxy = decoded
        }
        // Proxy is disabled by default per user preference
        if !defaults.bool(forKey: "proxy_explicitly_configured") {
            loadedProxy.isEnabled = false
        }
        proxy = loadedProxy

        var loadedWebDAV = WebDAVConfiguration()
        if let data = defaults.data(forKey: "webdav"),
           var decoded = try? decoder.decode(WebDAVConfiguration.self, from: data) {
            if let pass = try? keychain.get(.webDAVPassword) {
                decoded.password = pass
            }
            loadedWebDAV = decoded
        }
        webDAV = loadedWebDAV

        if let data = defaults.data(forKey: "geminiKeyStatuses"),
           let decoded = try? decoder.decode([String: GeminiKeyStatus].self, from: data) {
            keyStatuses = decoded
        }

        let storedKeysRaw = (try? keychain.get(.geminiAPIKeys)) ?? (try? keychain.get(.geminiAPIKey))
        var initialKeys: [String] = []
        if let storedKeysRaw, !storedKeysRaw.isEmpty {
            if let data = storedKeysRaw.data(using: .utf8),
               let decoded = try? decoder.decode([String].self, from: data) {
                initialKeys = decoded
            } else {
                initialKeys = storedKeysRaw.components(separatedBy: CharacterSet.newlines)
                    .flatMap { $0.components(separatedBy: ",") }
            }
        }
        let cleaned = initialKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        cachedGeminiAPIKeys = cleaned
        cachedGeminiAPIKey = cachedGeminiAPIKeys.first ?? ""
    }

    var geminiAPIKeys: [String] {
        get { cachedGeminiAPIKeys }
        set {
            let cleaned = newValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            cachedGeminiAPIKeys = cleaned
            cachedGeminiAPIKey = cachedGeminiAPIKeys.first ?? ""
            if let data = try? encoder.encode(cachedGeminiAPIKeys), let string = String(data: data, encoding: .utf8) {
                try? keychain.set(string, for: .geminiAPIKeys)
            }
            try? keychain.set(cachedGeminiAPIKey, for: .geminiAPIKey)
        }
    }

    var geminiAPIKey: String {
        get { geminiAPIKeys.first ?? "" }
        set {
            var updated = geminiAPIKeys
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !updated.isEmpty { updated.removeFirst() }
            } else {
                if updated.isEmpty { updated = [trimmed] }
                else { updated[0] = trimmed }
            }
            geminiAPIKeys = updated
        }
    }

    func status(for key: String) -> GeminiKeyStatus {
        keyStatuses[key] ?? .unchecked
    }

    func setKeyStatus(_ status: GeminiKeyStatus, for key: String) {
        keyStatuses[key] = status
        if let data = try? encoder.encode(keyStatuses) {
            defaults.set(data, forKey: "geminiKeyStatuses")
        }
    }

    func saveSecrets(geminiKeys: [String], proxyPassword: String, webDAVPassword: String) throws {
        geminiAPIKeys = geminiKeys
        try keychain.set(proxyPassword, for: .proxyPassword)
        try keychain.set(webDAVPassword, for: .webDAVPassword)
        proxy.password = proxyPassword
        webDAV.password = webDAVPassword
        persist()
    }

    func saveSecrets(geminiKey: String, proxyPassword: String, webDAVPassword: String) throws {
        try saveSecrets(geminiKeys: [geminiKey], proxyPassword: proxyPassword, webDAVPassword: webDAVPassword)
    }

    private func persist() {
        var publicWebDAV = webDAV
        publicWebDAV.password = ""
        defaults.set(try? encoder.encode(settings), forKey: "settings")
        if let data = try? encoder.encode(proxy), let value = String(data: data, encoding: .utf8) {
            try? keychain.set(value, for: .proxyConfiguration)
        }
        defaults.removeObject(forKey: "proxy")
        defaults.set(try? encoder.encode(publicWebDAV), forKey: "webdav")
    }
}
