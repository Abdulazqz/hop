import Foundation
import SwitcherCore

/// Hop's setup-tokens in the Keychain — one generic-password item per account UUID, read and written
/// through the same `security` tool Hop uses for the login item (so reads don't prompt under Hop's signing).
struct KeychainTokenStore: TokenStore {
    private func item(_ id: UUID) -> SecurityToolItem {
        SecurityToolItem(service: TokenStoreConst.service, account: id.uuidString)
    }

    func readToken(_ id: UUID) throws -> String? {
        guard let data = try item(id).read() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func writeToken(_ token: String, for id: UUID) throws {
        try item(id).write(Data(token.utf8))
    }

    func deleteToken(_ id: UUID) throws {
        try item(id).delete()
    }
}
