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
            loadedSettings.analysisModel = GeminiAPIClient.defaultAnalysisModel
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

    var transcriptionProviderID: String {
        get { settings.transcriptionProviderID }
        set {
            guard settings.transcriptionProviderID != newValue else { return }
            var updated = settings
            updated.transcriptionProviderID = newValue
            settings = updated
        }
    }

    var analysisProviderID: String {
        get { settings.analysisProviderID }
        set {
            guard settings.analysisProviderID != newValue else { return }
            var updated = settings
            updated.analysisProviderID = newValue
            updated.activeProviderID = newValue
            settings = updated
        }
    }

    var transcriptionUsesLocalWhisper: Bool {
        transcriptionProviderID == ProviderSelection.localWhisperID
    }

    var transcriptionProviderPreset: ProviderPreset? {
        ProviderPreset(rawValue: transcriptionProviderID)
    }

    var analysisProviderPreset: ProviderPreset? {
        ProviderPreset(rawValue: analysisProviderID)
    }

    func providerName(for providerID: String) -> String {
        if providerID == ProviderSelection.localWhisperID { return "Локальный Whisper" }
        if let preset = ProviderPreset(rawValue: providerID) { return preset.title }
        return customProviders.first { $0.id.uuidString == providerID }?.name.nonEmpty ?? "Свой провайдер"
    }

    func providerConfiguration(for providerID: String) -> ProviderConfiguration? {
        guard let preset = ProviderPreset(rawValue: providerID), preset != .gemini else { return nil }
        return configuration(for: preset)
    }

    func providerEndpoint(for providerID: String) -> URL? {
        if providerID == ProviderSelection.localWhisperID { return nil }
        if let preset = ProviderPreset(rawValue: providerID) {
            if preset == .gemini { return GeminiAPIClient.defaultBaseURL }
            let value = configuration(for: preset).baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
                  url.host != nil else { return nil }
            return url
        }
        return customProviders.first { $0.id.uuidString == providerID }?.endpoint
    }

    func providerTransport(for providerID: String) -> ProviderTransport {
        ProviderPreset(rawValue: providerID)?.transport ?? .gemini
    }

    func providerRequiresAPIKey(for providerID: String) -> Bool {
        ProviderPreset(rawValue: providerID)?.requiresAPIKey
            ?? customProviders.contains { $0.id.uuidString == providerID }
    }

    func providerAPIKeys(for providerID: String) -> [String] {
        if providerID == "gemini" { return geminiAPIKeys }
        let key = providerAPIKey(for: providerID)
        return key.isEmpty ? [] : [key]
    }

    func providerModel(for role: ProviderRole) -> String {
        let providerID = role == .transcription ? transcriptionProviderID : analysisProviderID
        if providerID == ProviderSelection.localWhisperID { return "whisper.cpp" }
        if let preset = ProviderPreset(rawValue: providerID) {
            if preset == .gemini {
                return role == .transcription ? settings.geminiModel : settings.analysisModel
            }
            let config = configuration(for: preset)
            let selected = role == .transcription ? config.transcriptionModel : config.analysisModel
            return selected.nonEmpty ?? (role == .transcription ? preset.defaultConfiguration.transcriptionModel : preset.defaultConfiguration.analysisModel)
        }
        if let provider = customProviders.first(where: { $0.id.uuidString == providerID }) {
            let selected = role == .transcription ? provider.transcriptionModel : provider.analysisModel
            return selected.nonEmpty ?? (role == .transcription ? settings.geminiModel : settings.analysisModel)
        }
        return role == .transcription ? settings.geminiModel : settings.analysisModel
    }

    func isProviderConfigured(_ providerID: String) -> Bool {
        if providerID == ProviderSelection.localWhisperID { return true }
        guard providerEndpoint(for: providerID) != nil else { return false }
        return !providerRequiresAPIKey(for: providerID) || !providerAPIKeys(for: providerID).isEmpty
    }

    var transcriptionProviderName: String { providerName(for: transcriptionProviderID) }
    var analysisProviderName: String { providerName(for: analysisProviderID) }
    var transcriptionProviderModel: String { providerModel(for: .transcription) }
    var analysisProviderModel: String { providerModel(for: .analysis) }
    var isTranscriptionProviderConfigured: Bool { isProviderConfigured(transcriptionProviderID) }
    var isAnalysisProviderConfigured: Bool { isProviderConfigured(analysisProviderID) }

    var activeProviderPreset: ProviderPreset? {
        ProviderPreset(rawValue: settings.activeProviderID)
    }

    var activeProvider: CustomProvider? {
        customProviders.first { $0.id.uuidString == settings.activeProviderID }
    }

    var activeProviderName: String {
        providerName(for: settings.activeProviderID)
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
        transcriptionProviderModel
    }

    var activeAnalysisModel: String {
        analysisProviderModel
    }

    /// The default Gemini analysis chain steps down only after the current
    /// model exhausts its three-attempt failure budget.
    var activeAnalysisFallbackModels: [String] {
        guard activeProviderTransport == .gemini,
              activeAnalysisModel == GeminiAPIClient.defaultAnalysisModel else { return [] }
        return GeminiAPIClient.defaultAnalysisFallbackModels
    }

    /// Compatibility accessor for callers that still need the first fallback.
    var activeAnalysisFallbackModel: String? {
        activeAnalysisFallbackModels.first
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

    var activeProviderRequiresAPIKey: Bool {
        if usesGemini { return true }
        if let preset = activeProviderPreset {
            return preset.requiresAPIKey
        }
        return activeProvider != nil
    }

    var isActiveProviderConfigured: Bool {
        guard activeProviderEndpoint != nil else { return false }
        if activeProviderRequiresAPIKey {
            return !activeProviderAPIKeys.isEmpty
        }
        return true
    }

    var activeProviderSupportsLiveTranscription: Bool {
        activeProviderPreset?.supportsLiveTranscription ?? false
    }

    var activeProviderSupportsRemoteTranscription: Bool {
        activeProviderPreset?.supportsRemoteTranscription ?? (activeProviderTransport != .anthropic)
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
        if webDAV.password.isEmpty {
            try? keychain.remove(.webDAVPassword, mode: secretStorageMode)
        } else {
            try? keychain.set(webDAV.password, for: .webDAVPassword, mode: secretStorageMode)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
