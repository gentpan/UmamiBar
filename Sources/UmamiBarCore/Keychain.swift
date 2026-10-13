import Foundation
import Security

public protocol CredentialStorage {
    func get(_ key: String) -> String?
    func set(_ value: String, for key: String) throws
}

public struct SystemCredentialStorage: CredentialStorage {
    public init() {}
    public func get(_ key: String) -> String? { Keychain.get(key) }
    public func set(_ value: String, for key: String) throws { try Keychain.set(value, for: key) }
}

public struct CredentialError: LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? {
        String(localized: "Could not save credentials to Keychain. Check Keychain access and try again.")
    }
}

public struct Keychain: Sendable {
    public static let service = "com.umamibar.app"

    public static func set(_ value: String, for key: String) throws {
        if value.isEmpty {
            delete(key)
            return
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addition = query
            addition[kSecValueData as String] = data
            addition[kSecAttrLabel as String] = "UmamiBar"
            let added = SecItemAdd(addition as CFDictionary, nil)
            guard added == errSecSuccess else { throw CredentialError(status: added) }
        } else if status != errSecSuccess {
            throw CredentialError(status: status)
        }
    }

    public static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
