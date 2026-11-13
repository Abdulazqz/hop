import Foundation

/// The active-account pointer: a tiny file holding only the active account's UUID (never a secret).
/// The helper re-reads it on every stale request, so switching accounts is a single small write.
public enum ActivePointer {
    /// The file's contents for a given account: the UUID string plus a trailing newline.
    public static func content(for id: UUID) -> String { id.uuidString + "\n" }

    /// The account the pointer names, or nil when the file is empty/garbage.
    public static func parse(_ text: String) -> UUID? {
        UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
