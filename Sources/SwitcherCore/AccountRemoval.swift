import Foundation

/// Cleanup decisions when the account set changes (pure). The Keychain deletes and the pointer
/// clear are IO done by Hop; this only decides what must happen so it can be tested.
public enum AccountRemoval {
    /// Ids whose stored token should be deleted, and whether the active pointer must be cleared,
    /// when the account set changes from `before` to `after`.
    public static func cleanup(before: [Account], after: [Account], active: UUID?)
        -> (removedTokenIDs: [UUID], clearPointer: Bool) {
        let afterIDs = Set(after.map(\.id))
        let removedTokenIDs = before.filter { !afterIDs.contains($0.id) && $0.tokenAddedAt != nil }.map(\.id)
        let clearPointer = active.map { !afterIDs.contains($0) } ?? false
        return (removedTokenIDs, clearPointer)
    }

    /// Every account id in `before` that is gone from `after` (its browser profile goes with it).
    public static func removedIDs(before: [Account], after: [Account]) -> [UUID] {
        let afterIDs = Set(after.map(\.id))
        return before.map(\.id).filter { !afterIDs.contains($0) }
    }
}
