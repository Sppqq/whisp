import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    var settings: WhispSettings { didSet { persist() } }
    var proxy: ProxyConfiguration { didSet { persist() } }
    var webDAV: WebDAVConfiguration { didSet { persist() } }
    var customProviders: [CustomProvider] { didSet { persist() } }

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cachedGeminiAPIKey = ""
    private var cachedGeminiAPIKeys: [String] = []
    private var cachedCustomProviderAPIKeys: [String: String] = [:]
    private(set) var secretStorageMode: SecretStorageMode
    var keyStatuses: [String: GeminiKeyStatus] = [:]

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        let decoder = JSONDecoder()
        let loadedStorageMode = SecretStorageMode(
            rawValue: defaults.string(forKey: "secretStorageMode") ?? ""
        ) ?? .localPreferences
        var loadedSettings = defaults.data(forKey: "settings")
            .flatMap { try? decoder.decode(WhispSettings.self, from: $0) } ?? WhispSettings()
        if loadedSettings.analysisModel == "gemini-3.7-flash" {
            loadedSettings.analysisModel = "gemini-3.8-flash"
        }

        self.defaults = defaults
        self.keychain = keychain
        secretStorageMode = loadedStorageMode
        settings = loadedSettings
        customProviders = defaults.data(forKey: "customProviders")
            .flatMap { try? decoder.decode([CustomProvider].self, from: $0) } ?? []

        var loadedProxy = ProxyConfiguration()
        if let configString = try? keychain.get(.proxyConfiguration, mode: loadedStorageMode),
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
            if let pass = try? keychain.get(.webDAVPassword, mode: loadedStorageMode) {
                decoded.password = pass
            }
            loadedWebDAV = decoded
        }
        webDAV = loadedWebDAV

        if let data = defaults.data(forKey: "geminiKeyStatuses"),
           let decoded = try? decoder.decode([String: GeminiKeyStatus].self, from: data) {
            keyStatuses = decoded
        }

        let storedKeysRaw = (try? keychain.get(.geminiAPIKeys, mode: loadedStorageMode))
            ?? (try? keychain.get(.geminiAPIKey, mode: loadedStorageMode))
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

        if let stored = try? keychain.get(.customProviderAPIKeys, mode: loadedStorageMode),
           let data = stored.data(using: .utf8),
           let decoded = try? decoder.decode([String: String].self, from: data) {
            cachedCustomProviderAPIKeys = decoded
        }
        if ProviderPreset(rawValue: settings.activeProviderID) == nil,
           !customProviders.contains(where: { $0.id.uuidString == settings.activeProviderID }) {
            settings.activeProviderID = "gemini"
        }
    }

    var geminiAPIKeys: [String] {
        get { cachedGeminiAPIKeys }
        set {
            let cleaned = newValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            cachedGeminiAPIKeys = cleaned
            cachedGeminiAPIKey = cachedGeminiAPIKeys.first ?? ""
            if let data = try? encoder.encode(cachedGeminiAPIKeys), let string = String(data: data, encoding: .utf8) {
                try? keychain.set(string, for: .geminiAPIKeys, mode: secretStorageMode)
            }
            try? keychain.set(cachedGeminiAPIKey, for: .geminiAPIKey, mode: secretStorageMode)
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

    var usesGemini: Bool { settings.activeProviderID == "gemini" }

    var activeProviderPreset: ProviderPreset? {
        ProviderPreset(rawValue: settings.activeProviderID)
    }

    var activeProvider: CustomProvider? {
        customProviders.first { $0.id.uuidString == settings.activeProviderID }
    }

    var activeProviderName: String {
        if let preset = activeProviderPreset { return preset.title }
        return activeProvider.flatMap { $0.name.nonEmpty } ?? "Свой провайдер"
    }

    var activeProviderAPIKeys: [String] {
        if usesGemini { return geminiAPIKeys }
        if activeProviderPreset != nil {
            let key = providerAPIKey(for: settings.activeProviderID)
            return key.isEmpty ? [] : [key]
        }
        guard let provider = activeProvider else { return [] }
        let key = customProviderAPIKey(for: provider)
        return key.isEmpty ? [] : [key]
    }

    var activeTranscriptionModel: String {
        if let preset = activeProviderPreset {
            if preset == .gemini { return settings.geminiModel }
            return configuration(for: preset).transcriptionModel.nonEmpty ?? preset.defaultConfiguration.transcriptionModel
        }
        return activeProvider?.transcriptionModel.nonEmpty ?? settings.geminiModel
    }

    var activeAnalysisModel: String {
        if let preset = activeProviderPreset {
            if preset == .gemini { return settings.analysisModel }
            return configuration(for: preset).analysisModel.nonEmpty ?? preset.defaultConfiguration.analysisModel
        }
        return activeProvider?.analysisModel.nonEmpty ?? settings.analysisModel
    }

    var activeProviderEndpoint: URL? {
        if let preset = activeProviderPreset {
            if preset == .gemini { return GeminiAPIClient.defaultBaseURL }
            let value = configuration(for: preset).baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
                  url.host != nil else { return nil }
            return url
        }
        return activeProvider?.endpoint
    }

    var activeProviderTransport: ProviderTransport {
        activeProviderPreset?.transport ?? .gemini
    }

    var activeProviderSupportsLiveTranscription: Bool {
        activeProviderPreset?.supportsLiveTranscription ?? false
    }

    func configuration(for preset: ProviderPreset) -> ProviderConfiguration {
        settings.providerConfigurations[preset.rawValue] ?? preset.defaultConfiguration
    }

    func setConfiguration(_ configuration: ProviderConfiguration, for preset: ProviderPreset) {
        var updatedSettings = settings
        updatedSettings.providerConfigurations[preset.rawValue] = configuration
        settings = updatedSettings
    }

    func providerAPIKey(for providerID: String) -> String {
        cachedCustomProviderAPIKeys[providerID] ?? ""
    }

    func saveProviderAPIKeys(_ apiKeys: [String: String]) throws {
        var merged = cachedCustomProviderAPIKeys
        for (providerID, value) in apiKeys {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { merged.removeValue(forKey: providerID) }
            else { merged[providerID] = trimmed }
        }
        let encoded = try encoder.encode(merged)
        try keychain.set(String(data: encoded, encoding: .utf8) ?? "{}", for: .customProviderAPIKeys, mode: secretStorageMode)
        cachedCustomProviderAPIKeys = merged
    }

    func customProviderAPIKey(for provider: CustomProvider) -> String {
        cachedCustomProviderAPIKeys[provider.id.uuidString] ?? ""
    }

    func saveCustomProviders(_ providers: [CustomProvider], apiKeys: [String: String]) throws {
        let allowedIDs = Set(providers.map { $0.id.uuidString })
        let cleanedKeys = apiKeys.reduce(into: [String: String]()) { result, entry in
            let key = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if allowedIDs.contains(entry.key), !key.isEmpty { result[entry.key] = key }
        }
        var mergedKeys = cachedCustomProviderAPIKeys.filter {
            allowedIDs.contains($0.key) || ProviderPreset(rawValue: $0.key) != nil
        }
        for (key, value) in cleanedKeys { mergedKeys[key] = value }
        let mergedEncoded = try encoder.encode(mergedKeys)
        try keychain.set(String(data: mergedEncoded, encoding: .utf8) ?? "{}", for: .customProviderAPIKeys, mode: secretStorageMode)
        cachedCustomProviderAPIKeys = mergedKeys
        customProviders = providers
        if activeProviderPreset == nil, activeProvider == nil { settings.activeProviderID = "gemini" }
        persist()
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
        try keychain.set(proxyPassword, for: .proxyPassword, mode: secretStorageMode)
        try keychain.set(webDAVPassword, for: .webDAVPassword, mode: secretStorageMode)
        proxy.password = proxyPassword
        webDAV.password = webDAVPassword
        persist()
    }

    func setSecretStorageMode(_ newMode: SecretStorageMode) throws {
        let previousMode = secretStorageMode
        guard newMode != previousMode else { return }

        let keysJSON = try encoder.encode(cachedGeminiAPIKeys)
        let customKeysJSON = try encoder.encode(cachedCustomProviderAPIKeys)
        let proxyJSON = try encoder.encode(proxy)
        let values: [SecretKey: String] = [
            .geminiAPIKeys: String(data: keysJSON, encoding: .utf8) ?? "[]",
            .geminiAPIKey: cachedGeminiAPIKey,
            .customProviderAPIKeys: String(data: customKeysJSON, encoding: .utf8) ?? "{}",
            .proxyPassword: proxy.password,
            .proxyConfiguration: String(data: proxyJSON, encoding: .utf8) ?? "{}",
            .webDAVPassword: webDAV.password
        ]

        do {
            for (key, value) in values where !value.isEmpty {
                try keychain.set(value, for: key, mode: newMode)
                guard try keychain.get(key, mode: newMode) == value else {
                    throw KeychainError.verificationFailed
                }
            }
        } catch {
            for key in SecretKey.allCases {
                try? keychain.remove(key, mode: newMode)
            }
            throw error
        }

        for key in SecretKey.allCases {
            try keychain.remove(key, mode: previousMode)
        }
        secretStorageMode = newMode
        defaults.set(newMode.rawValue, forKey: "secretStorageMode")
    }

    func saveSecrets(geminiKey: String, proxyPassword: String, webDAVPassword: String) throws {
        try saveSecrets(geminiKeys: [geminiKey], proxyPassword: proxyPassword, webDAVPassword: webDAVPassword)
    }

    private func persist() {
        var publicWebDAV = webDAV
        publicWebDAV.password = ""
        defaults.set(try? encoder.encode(settings), forKey: "settings")
        defaults.set(try? encoder.encode(customProviders), forKey: "customProviders")
        if let data = try? encoder.encode(proxy), let value = String(data: data, encoding: .utf8) {
            try? keychain.set(value, for: .proxyConfiguration, mode: secretStorageMode)
        }
        defaults.removeObject(forKey: "proxy")
        defaults.set(try? encoder.encode(publicWebDAV), forKey: "webdav")
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
