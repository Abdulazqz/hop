import Foundation
import Security
import SwitcherCore

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
    }
}

/// Claude Code's live login item plus Hop's own saved-login items, via the Security framework.
final class KeychainLoginStore: LoginStore {
    static let liveService = "Claude Code-credentials"
    static let savedService = "local.hop.login"

    func readLive() throws -> Data? { try read(service: Self.liveService, account: NSUserName()) }
    func writeLive(_ value: Data) throws { try write(value, service: Self.liveService, account: NSUserName()) }
    func deleteLive() throws { try delete(service: Self.liveService, account: NSUserName()) }
    func readSaved(_ accountID: UUID) throws -> Data? { try read(service: Self.savedService, account: accountID.uuidString) }
    func writeSaved(_ value: Data, for accountID: UUID) throws { try write(value, service: Self.savedService, account: accountID.uuidString) }
    func deleteSaved(_ accountID: UUID) throws { try delete(service: Self.savedService, account: accountID.uuidString) }

    private func query(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private func read(service: String, account: String) throws -> Data? {
        var q = query(service: service, account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }

    private func write(_ data: Data, service: String, account: String) throws {
        let q = query(service: service, account: account)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
            return
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private func delete(service: String, account: String) throws {
        let status = SecItemDelete(query(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
