import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
    case duplicateItem
    case itemNotFound
    case unhandledError(status: OSStatus)
    case dataConversionFailed

    public var errorDescription: String? {
        switch self {
        case .duplicateItem: return "Item already exists in Keychain."
        case .itemNotFound: return "Item not found in Keychain."
        case .unhandledError(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error (\(status))"
            return "Keychain error: \(msg)"
        case .dataConversionFailed: return "Data conversion failed."
        }
    }
}

/// Secure macOS Keychain wrapper for network credentials.
public final class KeychainStorage: Sendable {
    public static let shared = KeychainStorage()
    private let serviceName = "com.nexwave.networkworkbench"

    public init() {}

    public func save(secret: String, forKey key: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Update existing
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: key
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandledError(status: updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unhandledError(status: status)
        }
    }

    public func read(forKey key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw KeychainError.itemNotFound }
            throw KeychainError.unhandledError(status: status)
        }

        guard let data = item as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        return secret
    }

    public func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
}
