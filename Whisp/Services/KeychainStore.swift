import Foundation

enum SecretKey: String, CaseIterable, Sendable {
    case geminiAPIKey
    case geminiAPIKeys
    case proxyPassword
    case proxyConfiguration
    case webDAVPassword
}

struct KeychainStore: Sendable {
    // The app is locally/ad-hoc signed, so Keychain access control treats
    // every rebuild as a new client and can repeatedly show a password dialog.
    // Keep the existing abstraction, but use app-local preferences instead.
    private let prefix = "whisp.secret."

    func set(_ value: String, for key: SecretKey) throws {
        UserDefaults.standard.set(value, forKey: prefix + key.rawValue)
    }

    func get(_ key: SecretKey) throws -> String? {
        UserDefaults.standard.string(forKey: prefix + key.rawValue)
    }

    func remove(_ key: SecretKey) throws {
        UserDefaults.standard.removeObject(forKey: prefix + key.rawValue)
    }
}

enum KeychainError: LocalizedError {
    case unavailable
    var errorDescription: String? {
        "Не удалось сохранить секрет"
    }
}
