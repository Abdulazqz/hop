import Foundation

/// Write-to-temp-then-rename, so readers never see a half-written file.
public enum AtomicFile {
    /// Creates the parent directory if needed, and writes through a symlink (a dotfiles-managed
    /// settings.json, say) rather than replacing the link itself.
    public static func write(_ data: Data, to url: URL, permissions: Int = 0o600) throws {
        let target = url.resolvingSymlinksInPath()
        let directory = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".\(target.lastPathComponent).hop-\(UUID().uuidString)")
        try data.write(to: temp, options: [])
        do {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: temp.path)
            _ = try FileManager.default.replaceItemAt(target, withItemAt: temp, options: .usingNewMetadataOnly)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}
