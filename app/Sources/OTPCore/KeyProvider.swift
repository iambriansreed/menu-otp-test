import CryptoKit
import Foundation
import Security

/// Supplies the AES-256 key that encrypts accounts.enc.
public protocol KeyProvider {
    /// Returns the key, creating and persisting one only if none exists yet. Any other
    /// failure must throw: silently minting a new key would make the existing
    /// accounts.enc undecryptable.
    func key() throws -> SymmetricKey
}

public enum KeyProviderError: LocalizedError, Equatable {
    case keychain(OSStatus)
    case malformedKey

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            return "Keychain access failed: \(message) (OSStatus \(status))."
        case .malformedKey:
            return "The encryption key stored in the Keychain is malformed."
        }
    }
}

/// Demo mode and tests: a random key that lives only as long as this object.
public final class InMemoryKeyProvider: KeyProvider {
    private let stored = SymmetricKey(size: .bits256)
    public init() {}
    public func key() throws -> SymmetricKey { stored }
}

/// The real store: a random 256-bit key kept as a generic password in the login
/// Keychain, the native equivalent of Electron's safeStorage. The item's ACL trusts
/// the app that created it; since builds are ad-hoc signed, every new build is a
/// "different" app to the Keychain and macOS asks once whether to allow access
/// (Electron's ad-hoc builds behave the same way).
public final class KeychainKeyProvider: KeyProvider {
    public let service: String
    public let account: String
    private var cached: SymmetricKey?

    public init(service: String, account: String = "accounts-encryption-key") {
        self.service = service
        self.account = account
    }

    public func key() throws -> SymmetricKey {
        if let cached { return cached }
        let key = try read() ?? create()
        cached = key
        return key
    }

    /// Removes the Keychain item. Only used by tests.
    public func deleteItem() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read() throws -> SymmetricKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeyProviderError.keychain(status) }
        guard let data = result as? Data, data.count == 32 else { throw KeyProviderError.malformedKey }
        return SymmetricKey(data: data)
    }

    private func create() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        var query = baseQuery
        query[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        query[kSecAttrLabel as String] = "\(service) encryption key"
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyProviderError.keychain(status) }
        return key
    }
}
