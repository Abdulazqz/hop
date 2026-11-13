import Foundation
import SwitcherCore

enum HopLoginInstallError: Error, LocalizedError {
    case noInitialActive
    case foreignHelper(String)
    case unsafePath(String)
    var errorDescription: String? {
        switch self {
        case .noInitialActive: return "Choose which token-backed account to start active before enabling."
        case .unsafePath(let path):
            return "Hop can't be your Claude login from this home folder: Claude Code runs \(path) through the shell, "
                + "and the path has a space or shell character in it."
        case .foreignHelper(let path):
            return "Your ~/.claude/settings.json already sets apiKeyHelper to \(path). Remove it first if you want Hop to manage the login."
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
        let existing = try? Data(contentsOf: paths.settings)
        // Never clobber a user's own apiKeyHelper; refuse and let them remove it first.
        if let foreign = ClaudeSettings.foreignHelper(existing, hopPath: paths.helperScript.path) {
            throw HopLoginInstallError.foreignHelper(foreign)
        }
        // Claude Code runs the helper via `/bin/sh -c`; a home folder with a space would break every session.
        for path in [paths.helperScript.path, paths.pointer.path] where !HopLoginFiles.isShellSafe(path) {
            throw HopLoginInstallError.unsafePath(path)
        }
        // Validate the settings before touching anything, so a failed enable leaves no side effects.
        let merged = try ClaudeSettings.enableHelper(existing, helperPath: paths.helperScript.path, ttlMs: ttlMs)
        try writeHelperScript()
        try AtomicFile.write(Data(ActivePointer.content(for: initialActive).utf8), to: paths.pointer)
        try AtomicFile.write(merged, to: paths.settings)
    }

    func disable() throws {
        guard let existing = try? Data(contentsOf: paths.settings) else { return }
        let merged = try ClaudeSettings.disableHelper(existing)
        try AtomicFile.write(merged, to: paths.settings)
        // The helper script, pointer, Keychain tokens, and the Keychain login item are all left intact,
        // so Claude Code falls straight back to its normal login and re-enabling is instant.
    }

    /// Written atomically, so a session that runs the helper mid-write never execs a half-written script.
    private func writeHelperScript() throws {
        let text = HelperScript.contents(pointerPath: paths.pointer.path, tokenService: TokenStoreConst.service)
        try AtomicFile.write(Data(text.utf8), to: paths.helperScript, permissions: 0o700)
    }
}
