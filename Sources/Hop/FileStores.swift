import Foundation
import SwitcherCore

/// `~/.claude.json`, the file Claude Code keeps its identity block in.
struct IdentityDocumentFile: IdentityDocumentStore {
    let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")

    func read() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func write(_ document: Data) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try AtomicFile.write(document, to: url)
        } else {
            try document.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}

enum HopStateFile {
    static var url: URL { AccountStore.defaultURL.deletingLastPathComponent().appendingPathComponent("state.json") }
}
