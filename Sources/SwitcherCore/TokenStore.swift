import Foundation

/// Where Hop keeps each account's setup-token: one Keychain generic-password item per account.
public enum TokenStoreConst {
    /// Keychain service for Hop's own token items; the account field is the account's UUID.
    public static let service = "local.hop.token"
}

/// Reads/writes an account's `claude setup-token`. The live implementation keeps tokens in the Keychain,
/// so a token is never written to a plaintext file at rest.
public protocol TokenStore {
    func readToken(_ id: UUID) throws -> String?
    func writeToken(_ token: String, for id: UUID) throws
    func deleteToken(_ id: UUID) throws
}
