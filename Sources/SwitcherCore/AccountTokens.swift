import Foundation

/// Pure updates to an account's stored-token marker. The Keychain write/delete is IO done by Hop;
/// this only flips `tokenAddedAt` so the change is testable and the menu/model stay in sync.
public enum AccountTokens {
    /// Returns `accounts` with the target account's `tokenAddedAt` set to `date` (or cleared when nil).
    public static func apply(_ accounts: [Account], tokenAddedAt date: Date?, for id: UUID) -> [Account] {
        accounts.map { account in
            guard account.id == id else { return account }
            var updated = account
            updated.tokenAddedAt = date
            return updated
        }
    }
}
