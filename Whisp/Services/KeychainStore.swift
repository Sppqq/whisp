import Foundation
import Security

enum SecretStorageMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case localPreferences
    case keychain

    var id: Self { self }

    var title: String {
        switch self {
        case .localPreferences: "Локальные настройки"
        case .keychain: "macOS Keychain"
        }
    }

    var description: String {
        switch self {
        case .localPreferences:
            "Не вызывает системных запросов после пересборки, но хранит значения без шифрования."
        case .keychain:
            "Шифрует значения средствами macOS. После ad-hoc пересборки система может снова запросить доступ."
        }
    }

    var icon: String {
        switch self {
        case .localPreferences: "internaldrive"
        case .keychain: "lock.shield"
        }
    }
}

enum SecretKey: String, CaseIterable, Hashable, Sendable {
    case geminiAPIKey
    case geminiAPIKeys
    case proxyPassword
    case proxyConfiguration
    case webDAVPassword
}

struct KeychainStore: Sendable {
    private let preferencesPrefix = "whisp.secret."
    private let service = Bundle.main.bundleIdentifier ?? "app.whisp.lectures"

    func set(_ value: String, for key: SecretKey, mode: SecretStorageMode) throws {
        switch mode {
        case .localPreferences:
            UserDefaults.standard.set(value, forKey: preferencesPrefix + key.rawValue)
        case .keychain:
            try setKeychain(value, for: key)
        }
    }

    func get(_ key: SecretKey, mode: SecretStorageMode) throws -> String? {
        switch mode {
        case .localPreferences:
            UserDefaults.standard.string(forKey: preferencesPrefix + key.rawValue)
        case .keychain:
            try getKeychain(key)
        }
    }

    func remove(_ key: SecretKey, mode: SecretStorageMode) throws {
        switch mode {
        case .localPreferences:
            UserDefaults.standard.removeObject(forKey: preferencesPrefix + key.rawValue)
        case .keychain:
            let status = SecItemDelete(query(for: key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.status(status)
            }
        }
    }

    private func query(for key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }

    private func setKeychain(_ value: String, for key: SecretKey) throws {
        let data = Data(value.utf8)
        let baseQuery = query(for: key)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.status(updateStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.status(addStatus)
        }
    }

    private func getKeychain(_ key: SecretKey) throws -> String? {
        var item = query(for: key)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        // A release built with a different ad-hoc signature can otherwise wait
        // on a Keychain authorization dialog hidden behind the app window.
        item[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.status(status)
        }
        return value
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .status(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "код \(status)"
            return "Не удалось обратиться к macOS Keychain: \(detail)"
        case .verificationFailed:
            return "Не удалось проверить перенос секретов"
        }
    }
}
