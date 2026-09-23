import Foundation

public enum FolderPath {
    /// The profile folder Claude uses when launched without --user-data-dir.
    public static let defaultProfile = "~/Library/Application Support/Claude"

    /// Expands a leading "~" to `home`.
    public static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + String(path.dropFirst()) }
        return path
    }

    /// Canonical form for comparing folders. `nil`, empty, or whitespace-only means the default profile.
    public static func normalize(_ folder: String?, home: String) -> String {
        let expanded = expand(isBlank(folder) ? defaultProfile : folder!, home: home)
        return URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// `true` for `nil`, empty, or whitespace-only — all of which mean the default profile.
    static func isBlank(_ folder: String?) -> Bool {
        guard let folder else { return true }
        return folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A folder the switcher may move to the Trash: directly inside ~/Library/Application Support,
    /// named Claude-*, and not the default profile.
    public static func isTrashable(_ folder: String?, home: String) -> Bool {
        guard !isBlank(folder) else { return false }
        let normalized = normalize(folder, home: home)
        let url = URL(fileURLWithPath: normalized)
        guard url.deletingLastPathComponent().path == normalize("~/Library/Application Support", home: home) else {
            return false
        }
        guard url.lastPathComponent.hasPrefix("Claude-") else { return false }
        return normalized != normalize(nil, home: home)
    }
}
