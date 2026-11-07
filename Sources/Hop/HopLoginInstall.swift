import Foundation
import SwitcherCore

enum HopLoginInstallError: Error, LocalizedError {
    case noInitialActive
    var errorDescription: String? {
        switch self {
        case .noInitialActive: return "Choose which token-backed account to start active before enabling."
        }
    }
}

/// Installs or reverts "Hop is my Claude login": writes the helper script (chmod 0700), the active-account
/// pointer, and merges `apiKeyHelper` into `~/.claude/settings.json`. Every transform is a pure SwitcherCore
/// unit (HelperScript, ActivePointer, ClaudeSettings); this type only does the IO. Paths are injectable so it
/// can be exercised against a throwaway config dir without touching the real `~/.claude`.
struct HopLoginInstall {
    struct Paths {
        var settings: URL
        var helperScript: URL
        var pointer: URL
        static var production: Paths {
            Paths(settings: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json"),
                  helperScript: HopHelperScriptFile.url,
                  pointer: ActivePointerFile.url)
        }
    }

    /// Proven in the 2026-11-07 spike: a 3s TTL lands a switch on the next turn (often mid-turn) while an
    /// idle session still doesn't refetch. Short enough to feel live, long enough not to refetch every request.
    static let defaultTTLMs = 3000

    let paths: Paths
    let ttlMs: Int

    init(paths: Paths = .production, ttlMs: Int = HopLoginInstall.defaultTTLMs) {
        self.paths = paths
        self.ttlMs = ttlMs
    }

    func isEnabled() -> Bool {
        ClaudeSettings.isHelperEnabled(try? Data(contentsOf: paths.settings), helperPath: paths.helperScript.path)
    }

    func enable(initialActive: UUID?) throws {
        guard let initialActive else { throw HopLoginInstallError.noInitialActive }
        try writeHelperScript()
        try AtomicFile.write(Data(ActivePointer.content(for: initialActive).utf8), to: paths.pointer)
        let existing = try? Data(contentsOf: paths.settings)
        let merged = try ClaudeSettings.enableHelper(existing, helperPath: paths.helperScript.path, ttlMs: ttlMs)
        try createParent(of: paths.settings)
        try AtomicFile.write(merged, to: paths.settings)
    }

    func disable() throws {
        guard let existing = try? Data(contentsOf: paths.settings) else { return }
        let merged = try ClaudeSettings.disableHelper(existing)
        try AtomicFile.write(merged, to: paths.settings)
        // The helper script, pointer, Keychain tokens, and the Keychain login item are all left intact,
        // so Claude Code falls straight back to its normal login and re-enabling is instant.
    }

    private func writeHelperScript() throws {
        try createParent(of: paths.helperScript)
        let text = HelperScript.contents(pointerPath: paths.pointer.path, tokenService: TokenStoreConst.service)
        try Data(text.utf8).write(to: paths.helperScript, options: [])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.helperScript.path)
    }

    private func createParent(of url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
}
