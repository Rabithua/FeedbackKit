import CryptoKit
import Foundation
import Security

public protocol FeedbackVisitorCredentialProviding: Sendable {
    func credential(for productKey: String) async throws -> String
    func deleteCredential(for productKey: String) async throws
}

public actor FeedbackVisitorCredentialStore: FeedbackVisitorCredentialProviding {
    private let service: String

    public init(service: String = "ink.rote.FeedbackKit.visitor") {
        self.service = service
    }

    public func credential(for productKey: String) throws -> String {
        let account = accountName(productKey)
        if let current = try load(account) { return base64URL(current) }
        var data = Data(count: 32)
        let status = data.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, 32, address)
        }
        guard status == errSecSuccess else { throw keychainError(status) }
        try save(data, account: account)
        return base64URL(data)
    }

    public func deleteCredential(for productKey: String) throws {
        let status = SecItemDelete(query(accountName(productKey)) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private func accountName(_ productKey: String) -> String {
        SHA256.hash(data: Data(productKey.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func load(_ account: String) throws -> Data? {
        var attributes = query(account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw keychainError(status)
        }
        if data.count != 32 {
            _ = SecItemDelete(query(account) as CFDictionary)
            return nil
        }
        return data
    }

    private func save(_ data: Data, account: String) throws {
        var attributes = query(account)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = false
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw keychainError(status)
        }
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func keychainError(_ status: OSStatus) -> FeedbackClientError {
        FeedbackClientError(
            kind: .transport,
            context: FeedbackFailureContext(
                debugDescription: "Keychain status \(status)"
            )
        )
    }
}
