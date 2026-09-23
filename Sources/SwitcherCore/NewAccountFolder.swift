import Foundation

public enum NewAccountFolder {
    /// "My Work Acct" -> "my-work-acct". Falls back to "account" when nothing ASCII is left.
    public static func slug(_ name: String) -> String {
        var out = ""
        for ch in name.lowercased() {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                out.append(ch)
            } else if ch == " " || ch == "-" || ch == "_", !out.isEmpty, out.last != "-" {
                out.append("-")
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "account" : out
    }

    /// First `~/Library/Application Support/Claude-<slug>[-N]` that no account uses.
    /// With `skipExistingOnDisk`, also skips folders that already exist.
    public static func candidate(
        forName name: String,
        accounts: [Account],
        home: String,
        skipExistingOnDisk: Bool = false,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String {
        let claimed = Set(accounts.map { FolderPath.normalize($0.folder, home: home) })
        let base = "~/Library/Application Support/Claude-" + slug(name)
        var n = 1
        while true {
            let folder = n == 1 ? base : "\(base)-\(n)"
            let normalized = FolderPath.normalize(folder, home: home)
            if !claimed.contains(normalized) && !(skipExistingOnDisk && fileExists(normalized)) {
                return folder
            }
            n += 1
        }
    }
}
