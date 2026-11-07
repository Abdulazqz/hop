import Foundation

/// Write-to-temp-then-rename, so readers never see a half-written file.
public enum AtomicFile {
    public static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".\(url.lastPathComponent).hop-\(UUID().uuidString)")
        try data.write(to: temp, options: [])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp, options: .usingNewMetadataOnly)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}
